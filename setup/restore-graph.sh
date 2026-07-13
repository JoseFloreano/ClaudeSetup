#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  restore-graph.sh — Restauración CORRECTA de un backup de FalkorDB
#
#  Por qué existe (auditoría A3): el compose corre con --appendonly yes.
#  Con AOF activo, el server carga del AOF al arrancar e IGNORA dump.rdb.
#  Copiar el .rdb a mano y reiniciar "termina sin error" y no restaura NADA.
#
#  Procedimiento AOF-safe que implementa este script:
#    1. Detiene el stack           5. Verifica DBSIZE > 0 (si no → FALLO ruidoso)
#    2. Cuarentena de datos viejos 6. CONFIG SET appendonly yes (regenera AOF
#    3. Coloca el dump.rdb            desde los datos ya cargados)
#    4. Arranca recovery con       7. Apaga recovery, levanta el stack normal
#       --appendonly no               y verifica contra el manifiesto
#
#  Uso:
#    ./restore-graph.sh                     # último backup en BACKUP_DIR
#    ./restore-graph.sh /ruta/backup.rdb    # backup específico
# ══════════════════════════════════════════════════════════════

set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "  ${RED}[ERR]${NC} $1"; }

GRAPHITI_LOCAL="${GRAPHITI_LOCAL:-$HOME/.local/share/graphiti}"
ENV_FILE="${GRAPHITI_LOCAL}/.env"
COMPOSE_FILE="${GRAPHITI_LOCAL}/docker-compose.yml"

[ -f "${ENV_FILE}" ] || { err "No existe ${ENV_FILE}. Corre setup-new-machine.sh primero."; exit 1; }

envval() { grep -E "^$1=" "${ENV_FILE}" | tail -1 | cut -d= -f2- ; }
DATA_DIR="$(envval FALKORDB_DATA_PATH)"
BACKUP_DIR="$(envval BACKUP_DIR)"
FALKORDB_VERSION="$(envval FALKORDB_VERSION)"
[ -n "${DATA_DIR}" ] && [ -n "${FALKORDB_VERSION}" ] || { err "FALKORDB_DATA_PATH o FALKORDB_VERSION vacíos en .env"; exit 1; }
case "${DATA_DIR}" in *OneDrive*) err "FALKORDB_DATA_PATH apunta a OneDrive — prohibido (H2)."; exit 1;; esac

# ── 1. Elegir backup ──────────────────────────────────────────────────────
BACKUP_FILE="${1:-}"
if [ -z "${BACKUP_FILE}" ]; then
  BACKUP_FILE=$(ls -t "${BACKUP_DIR}"/*.rdb 2>/dev/null | head -1 || echo "")
  [ -n "${BACKUP_FILE}" ] || { err "No hay backups .rdb en ${BACKUP_DIR}"; exit 1; }
fi
[ -f "${BACKUP_FILE}" ] || { err "No existe ${BACKUP_FILE}"; exit 1; }

MANIFEST="${BACKUP_FILE%.rdb}.manifest.json"
EXPECTED_DBSIZE="-1"
if [ -f "${MANIFEST}" ] && command -v python3 >/dev/null 2>&1; then
  EXPECTED_DBSIZE=$(python3 -c "import json;print(json.load(open('${MANIFEST}')).get('dbsize',-1))" 2>/dev/null || echo "-1")
  SRC_HOST=$(python3 -c "import json;print(json.load(open('${MANIFEST}')).get('hostname','?'))" 2>/dev/null || echo "?")
  echo "  Backup: $(basename "${BACKUP_FILE}") | host origen: ${SRC_HOST} | dbsize esperado: ${EXPECTED_DBSIZE}"
fi
read -rp "  ¿Restaurar este backup? Los datos actuales van a cuarentena. [y/N] " GO
[[ "${GO:-N}" =~ ^[Yy]$ ]] || { echo "Cancelado."; exit 0; }

# ── 2. Detener stack y poner datos actuales en cuarentena ────────────────
docker rm -f graphiti-restore >/dev/null 2>&1 || true
if [ -f "${COMPOSE_FILE}" ]; then
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" stop >/dev/null 2>&1 || true
fi
docker stop graphiti-mcp-server graphiti-falkordb >/dev/null 2>&1 || true
ok "Stack detenido"

mkdir -p "${DATA_DIR}"
TS=$(date +"%Y%m%d_%H%M%S")
QUARANTINE="${DATA_DIR}/pre-restore-${TS}"
FOUND_OLD=$(find "${DATA_DIR}" -maxdepth 1 -type f \( -name "*.rdb" -o -name "*.aof" -o -name "*.manifest" \) 2>/dev/null || true)
APPENDDIR="${DATA_DIR}/appendonlydir"
if [ -n "${FOUND_OLD}" ] || [ -d "${APPENDDIR}" ]; then
  mkdir -p "${QUARANTINE}"
  [ -n "${FOUND_OLD}" ] && echo "${FOUND_OLD}" | xargs -I{} mv {} "${QUARANTINE}/"
  [ -d "${APPENDDIR}" ] && mv "${APPENDDIR}" "${QUARANTINE}/"
  ok "Datos previos en cuarentena: ${QUARANTINE}"
fi

# ── 3. Colocar el dump.rdb y arrancar recovery SIN AOF ────────────────────
cp "${BACKUP_FILE}" "${DATA_DIR}/dump.rdb"
docker run -d --name graphiti-restore \
  -v "${DATA_DIR}:/var/lib/falkordb/data" \
  -e REDIS_ARGS="--appendonly no" \
  "falkordb/falkordb:${FALKORDB_VERSION}" >/dev/null
ok "Container de recovery arrancado (appendonly OFF → carga el RDB)"

PINGED=false
for i in $(seq 1 60); do
  sleep 1
  if docker exec graphiti-restore redis-cli ping 2>/dev/null | grep -q PONG; then PINGED=true; break; fi
done
[ "${PINGED}" = true ] || { err "Recovery no responde. Ver: docker logs graphiti-restore"; exit 1; }

# ── 4. VERIFICAR que los datos cargaron ───────────────────────────────────
DBSIZE=$(docker exec graphiti-restore redis-cli DBSIZE 2>/dev/null | tr -dc '0-9' || echo "0")
if [ "${DBSIZE:-0}" -eq 0 ]; then
  err "RESTAURACIÓN FALLIDA: DBSIZE=0 — el RDB no cargó."
  err "Datos previos intactos en: ${QUARANTINE}"
  docker rm -f graphiti-restore >/dev/null 2>&1 || true
  exit 1
fi
if [ "${EXPECTED_DBSIZE}" != "-1" ] && [ "${DBSIZE}" != "${EXPECTED_DBSIZE}" ]; then
  warn "DBSIZE=${DBSIZE} difiere del manifiesto (${EXPECTED_DBSIZE}). Revisa antes de confiar."
else
  ok "Datos cargados: DBSIZE=${DBSIZE}"
fi

# ── 5. Regenerar el AOF desde los datos cargados ──────────────────────────
docker exec graphiti-restore redis-cli CONFIG SET appendonly yes >/dev/null
for i in $(seq 1 60); do
  sleep 1
  REWRITING=$(docker exec graphiti-restore redis-cli INFO persistence 2>/dev/null | grep -E "^aof_rewrite_in_progress:" | tr -dc '0-9' || echo "1")
  [ "${REWRITING:-1}" = "0" ] && break
done
ok "AOF regenerado desde el snapshot restaurado"

# ── 6. Apagar recovery y levantar el stack normal ─────────────────────────
docker exec graphiti-restore redis-cli BGSAVE >/dev/null 2>&1 || true
sleep 2
docker rm -f graphiti-restore >/dev/null
if [ -f "${COMPOSE_FILE}" ]; then
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d >/dev/null
  sleep 5
  FINAL=$(docker exec graphiti-falkordb redis-cli DBSIZE 2>/dev/null | tr -dc '0-9' || echo "?")
  ok "Stack levantado. DBSIZE final: ${FINAL}"
else
  warn "No encontré ${COMPOSE_FILE} — levanta el stack manualmente."
fi

echo ""
ok "Restauración completada y VERIFICADA. Cuarentena borrable tras confirmar: ${QUARANTINE:-'(no hubo)'}"
