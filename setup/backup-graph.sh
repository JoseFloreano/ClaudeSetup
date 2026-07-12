#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  backup-graph.sh — Snapshot RDB de FalkorDB → OneDrive
#  Cron sugerido: 0 */4 * * * /path/to/backup-graph.sh
#  También útil: ejecutar antes de apagar/cambiar de laptop.
#
#  Uso:
#    ./backup-graph.sh                          # usa defaults
#    ./backup-graph.sh ~/OneDrive               # OneDrive path explícito
#    ONEDRIVE_PATH=/ruta backup-graph.sh        # via env var
# ══════════════════════════════════════════════════════════════

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-graphiti-falkordb}"
ONEDRIVE_PATH="${1:-${ONEDRIVE_PATH:-$HOME/OneDrive}}"
BACKUP_DIR="${ONEDRIVE_PATH}/DevSetup/graphiti-data/backups"
MAX_BACKUPS="${MAX_BACKUPS:-15}"

# ── 1. Verificar container ────────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  echo "[WARN] Container '${CONTAINER_NAME}' no está corriendo. Backup omitido."
  exit 0
fi

# ── 2. Crear directorio de backup ─────────────────────────────────────────
mkdir -p "${BACKUP_DIR}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ── 3. Trigger BGSAVE (no-blocking) ──────────────────────────────────────
echo "[INFO] Triggering BGSAVE en FalkorDB..."
BEFORE_SAVE=$(docker exec "${CONTAINER_NAME}" redis-cli LASTSAVE 2>/dev/null || echo "0")
docker exec "${CONTAINER_NAME}" redis-cli BGSAVE > /dev/null 2>&1 || true

# Esperar a que el snapshot termine (max 30s)
MAX_WAIT=30
SAVED=false
for i in $(seq 1 $MAX_WAIT); do
  sleep 1
  AFTER_SAVE=$(docker exec "${CONTAINER_NAME}" redis-cli LASTSAVE 2>/dev/null || echo "0")
  if [ "$AFTER_SAVE" != "$BEFORE_SAVE" ]; then
    echo "[INFO] BGSAVE completado (${i}s)."
    SAVED=true
    break
  fi
done
if [ "$SAVED" = false ]; then
  echo "[WARN] BGSAVE no confirmado en ${MAX_WAIT}s. Copiando de todas formas."
fi

# ── 4. Copiar dump.rdb ────────────────────────────────────────────────────
BACKUP_FILE="${BACKUP_DIR}/graphiti_${TIMESTAMP}.rdb"

# Intentar varias rutas posibles donde FalkorDB guarda el RDB
COPIED=false
for DATA_PATH in "/var/lib/falkordb/data/dump.rdb" "/data/dump.rdb"; do
  if docker exec "${CONTAINER_NAME}" test -f "${DATA_PATH}" 2>/dev/null; then
    docker cp "${CONTAINER_NAME}:${DATA_PATH}" "${BACKUP_FILE}" 2>/dev/null && {
      echo "[OK] Backup guardado: ${BACKUP_FILE}"
      COPIED=true
      break
    }
  fi
done

if [ "$COPIED" = false ]; then
  echo "[WARN] No se encontró dump.rdb. Si usas bind mount en OneDrive, el archivo"
  echo "       ya está en ${ONEDRIVE_PATH}/DevSetup/graphiti-data/falkordb/"
fi

# ── 5. También copiar AOF para mayor durabilidad ─────────────────────────
AOF_BACKUP="${BACKUP_DIR}/graphiti_${TIMESTAMP}.aof"
for AOF_PATH in "/var/lib/falkordb/data/appendonly.aof" "/data/appendonly.aof"; do
  if docker exec "${CONTAINER_NAME}" test -f "${AOF_PATH}" 2>/dev/null; then
    docker cp "${CONTAINER_NAME}:${AOF_PATH}" "${AOF_BACKUP}" 2>/dev/null && break
  fi
done

# ── 6. Crear manifiesto del backup ───────────────────────────────────────
MANIFEST="${BACKUP_DIR}/graphiti_${TIMESTAMP}.manifest.json"
GRAPH_INFO=$(docker exec "${CONTAINER_NAME}" redis-cli INFO keyspace 2>/dev/null || echo "unavailable")
cat > "${MANIFEST}" << MANIFEST_EOF
{
  "timestamp": "${TIMESTAMP}",
  "container": "${CONTAINER_NAME}",
  "hostname": "$(hostname)",
  "rdb_file": "graphiti_${TIMESTAMP}.rdb",
  "graph_info": "${GRAPH_INFO}",
  "restore_cmd": "docker cp graphiti_${TIMESTAMP}.rdb graphiti-falkordb:/var/lib/falkordb/data/dump.rdb && docker restart graphiti-falkordb"
}
MANIFEST_EOF
echo "[INFO] Manifiesto: ${MANIFEST}"

# ── 7. Limpiar backups viejos (mantener últimos MAX_BACKUPS) ─────────────
OLD_BACKUPS=$(ls -t "${BACKUP_DIR}"/*.rdb 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)))
if [ -n "$OLD_BACKUPS" ]; then
  echo "$OLD_BACKUPS" | xargs rm -f
  # Limpiar manifiestos huérfanos también
  ls -t "${BACKUP_DIR}"/*.manifest.json 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f 2>/dev/null || true
  echo "[INFO] Backups viejos limpiados."
fi

# ── 8. Verificar espacio en OneDrive ─────────────────────────────────────
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "?")
echo "[INFO] Tamaño total de backups: ${BACKUP_SIZE} en ${BACKUP_DIR}"
echo "[DONE] Backup completado: $(date)"
