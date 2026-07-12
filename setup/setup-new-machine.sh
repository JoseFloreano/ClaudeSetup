#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  setup-new-machine.sh — Bootstrap Graphiti en laptop nueva
#
#  Prerequisitos:
#    - Docker Desktop instalado y corriendo
#    - OneDrive sincronizado (DevSetup/ debe existir)
#    - claude CLI instalado (Claude Code)
#
#  Uso:
#    bash setup-new-machine.sh                   # OneDrive en ~/OneDrive
#    bash setup-new-machine.sh /ruta/a/OneDrive  # path explícito
# ══════════════════════════════════════════════════════════════

set -euo pipefail
ONEDRIVE="${1:-$HOME/OneDrive}"
DEVSETUP="${ONEDRIVE}/DevSetup"
GRAPHITI_DATA="${DEVSETUP}/graphiti-data"
GRAPHITI_DOCKER="${DEVSETUP}/graphiti-docker"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

header() { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }
ok()     { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
err()    { echo -e "  ${RED}[ERR]${NC} $1"; }
info()   { echo -e "  ${BLUE}[INFO]${NC} $1"; }

echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Graphiti + FalkorDB — Setup nueva máquina${NC}"
echo -e "${BOLD} OneDrive: ${ONEDRIVE}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"

# ── 1. Verificar dependencias ──────────────────────────────────────────────
header "Verificando dependencias"
ERRORS=0

command -v docker >/dev/null 2>&1 && ok "Docker instalado" || { err "Docker no encontrado. Instala Docker Desktop."; ERRORS=$((ERRORS+1)); }
(docker compose version >/dev/null 2>&1 || docker-compose --version >/dev/null 2>&1) && ok "Docker Compose disponible" || { err "Docker Compose no disponible."; ERRORS=$((ERRORS+1)); }
[ -d "${DEVSETUP}" ] && ok "OneDrive/DevSetup encontrado" || { warn "No se encontró ${DEVSETUP}. Creando..."; mkdir -p "${DEVSETUP}"; }

if [ $ERRORS -gt 0 ]; then
  err "Hay $ERRORS errores críticos. Corrige antes de continuar."
  exit 1
fi

# ── 2. Crear estructura de directorios ────────────────────────────────────
header "Creando directorios en OneDrive"
mkdir -p "${GRAPHITI_DATA}/falkordb"
mkdir -p "${GRAPHITI_DATA}/backups"
mkdir -p "${GRAPHITI_DATA}/config"
mkdir -p "${GRAPHITI_DOCKER}"
ok "Directorios creados en ${GRAPHITI_DATA}"

# ── 3. Copiar archivos de config desde dotfiles o descargar ───────────────
header "Configurando archivos"
DOTFILES="${DEVSETUP}/claude-dotfiles"

# Copiar docker-compose.yml
if [ -f "${DOTFILES}/graphiti/docker-compose.yml" ]; then
  cp "${DOTFILES}/graphiti/docker-compose.yml" "${GRAPHITI_DOCKER}/"
  ok "docker-compose.yml copiado desde dotfiles"
elif [ -f "${GRAPHITI_DOCKER}/docker-compose.yml" ]; then
  ok "docker-compose.yml ya existe"
else
  warn "Descargando docker-compose.yml de GitHub..."
  curl -fsSL "https://raw.githubusercontent.com/getzep/graphiti/main/mcp_server/docker/docker-compose.falkordb.yaml" \
    -o "${GRAPHITI_DOCKER}/docker-compose.yml" 2>/dev/null && ok "Descargado" || warn "Descarga fallida. Copia manualmente."
fi

# Copiar config.yaml
if [ -f "${DOTFILES}/graphiti/config.yaml" ]; then
  cp "${DOTFILES}/graphiti/config.yaml" "${GRAPHITI_DATA}/config/"
  ok "config.yaml copiado"
elif [ -f "${GRAPHITI_DATA}/config/config.yaml" ]; then
  ok "config.yaml ya existe en OneDrive"
else
  warn "config.yaml no encontrado. Créalo manualmente en ${GRAPHITI_DATA}/config/"
fi

# ── 4. Crear .env con rutas del sistema actual ────────────────────────────
header "Creando .env"
ENV_FILE="${GRAPHITI_DOCKER}/.env"

if [ -f "${ENV_FILE}" ]; then
  info ".env ya existe. No sobreescrito."
else
  cat > "${ENV_FILE}" << ENVEOF
# Auto-generado por setup-new-machine.sh en $(hostname) — $(date)
FALKORDB_DATA_PATH=${GRAPHITI_DATA}/falkordb
CONFIG_PATH=${GRAPHITI_DATA}/config

# RELLENA ESTAS KEYS:
LLM_PROVIDER=openai
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

MODEL_NAME=gpt-4.1-mini
SMALL_MODEL_NAME=gpt-4.1-nano

FALKORDB_PASSWORD=
SEMAPHORE_LIMIT=3
ENVEOF
  ok ".env creado"
  warn "IMPORTANTE: Edita ${ENV_FILE} y agrega tus API keys antes de continuar."
  echo ""
  read -rp "  ¿Editar .env ahora? [y/N] " EDIT
  if [[ "${EDIT:-N}" =~ ^[Yy]$ ]]; then
    "${EDITOR:-nano}" "${ENV_FILE}"
  fi
fi

# ── 5. Verificar que haya API key ─────────────────────────────────────────
if grep -q "^OPENAI_API_KEY=$\|^ANTHROPIC_API_KEY=$" "${ENV_FILE}" 2>/dev/null; then
  warn "Las API keys están vacías en ${ENV_FILE}."
  warn "El servidor MCP arrancará pero fallará al procesar episodios."
fi

# ── 6. Agregar Graphiti al MCP de Claude Code ────────────────────────────
header "Configurando MCP en Claude Code"
if command -v claude >/dev/null 2>&1; then
  # Verificar si ya está configurado
  if claude mcp list 2>/dev/null | grep -q "graphiti"; then
    ok "MCP 'graphiti-memory' ya configurado"
  else
    claude mcp add --transport http graphiti-memory "http://localhost:8000/mcp/" -s user 2>/dev/null && \
      ok "MCP graphiti-memory agregado (scope: user)" || \
      warn "No se pudo agregar automáticamente. Agrega manualmente:"
    echo "         claude mcp add --transport http graphiti-memory http://localhost:8000/mcp/ -s user"
  fi
else
  warn "Claude Code CLI no encontrado. Agrega el MCP manualmente:"
  echo "       claude mcp add --transport http graphiti-memory http://localhost:8000/mcp/ -s user"
fi

# ── 7. Restaurar desde backup si existe ───────────────────────────────────
header "Verificando backups existentes"
LATEST_BACKUP=$(ls -t "${GRAPHITI_DATA}/backups/"*.rdb 2>/dev/null | head -1 || echo "")
if [ -n "${LATEST_BACKUP}" ]; then
  BACKUP_DATE=$(basename "${LATEST_BACKUP}" | sed 's/graphiti_\(.*\)\.rdb/\1/')
  info "Backup encontrado: ${LATEST_BACKUP} (${BACKUP_DATE})"
  echo ""
  read -rp "  ¿Restaurar desde este backup? [y/N] " RESTORE
  if [[ "${RESTORE:-N}" =~ ^[Yy]$ ]]; then
    mkdir -p "${GRAPHITI_DATA}/falkordb"
    cp "${LATEST_BACKUP}" "${GRAPHITI_DATA}/falkordb/dump.rdb"
    ok "Backup restaurado. FalkorDB cargará el grafo al arrancar."
  fi
else
  info "No hay backups previos. Se iniciará con grafo vacío."
fi

# ── 8. Levantar containers ────────────────────────────────────────────────
header "Levantando Docker containers"
cd "${GRAPHITI_DOCKER}"
docker compose up -d && ok "Containers levantados" || { err "Error al levantar containers."; exit 1; }

# ── 9. Health check ───────────────────────────────────────────────────────
header "Verificando health (espera 10s...)"
sleep 10

FALKORDB_OK=false
MCP_OK=false

if docker exec graphiti-falkordb redis-cli ping 2>/dev/null | grep -q PONG; then
  ok "FalkorDB respondiendo"
  FALKORDB_OK=true
else
  warn "FalkorDB no responde aún. Verifica: docker logs graphiti-falkordb"
fi

if curl -sf "http://localhost:8000/mcp/" >/dev/null 2>&1 || \
   curl -sf "http://localhost:8000/" >/dev/null 2>&1; then
  ok "MCP Server respondiendo en http://localhost:8000/mcp/"
  MCP_OK=true
else
  warn "MCP Server no responde aún. Espera 30s más y verifica: docker logs graphiti-mcp-server"
fi

# ── 10. Configurar backup automático ─────────────────────────────────────
header "Configurando backup automático"
BACKUP_SCRIPT="${DEVSETUP}/graphiti-docker/backup-graph.sh"
if [ -f "${DOTFILES}/graphiti/scripts/backup-graph.sh" ]; then
  cp "${DOTFILES}/graphiti/scripts/backup-graph.sh" "${BACKUP_SCRIPT}"
  chmod +x "${BACKUP_SCRIPT}"
fi

if command -v crontab >/dev/null 2>&1; then
  # Agregar al cron si no existe ya
  CRON_LINE="0 */4 * * * ONEDRIVE_PATH=${ONEDRIVE} ${BACKUP_SCRIPT}"
  if ! crontab -l 2>/dev/null | grep -q "backup-graph"; then
    (crontab -l 2>/dev/null; echo "${CRON_LINE}") | crontab -
    ok "Cron configurado: backup cada 4 horas"
  else
    ok "Cron para backup ya existe"
  fi
fi

# ── Resumen final ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Setup ${FALKORDB_OK && $MCP_OK && echo "completado ✓" || echo "con advertencias ⚠"}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
echo ""
echo "  FalkorDB Browser UI : http://localhost:3000"
echo "  MCP endpoint        : http://localhost:8000/mcp/"
echo "  Datos del grafo     : ${GRAPHITI_DATA}/falkordb/"
echo "  Backups             : ${GRAPHITI_DATA}/backups/"
echo ""
echo "  Próximos pasos:"
echo "  1. Edita ${ENV_FILE} si aún no tienes las API keys."
echo "  2. Reinicia si cambias .env:"
echo "       cd ${GRAPHITI_DOCKER} && docker compose restart graphiti-mcp"
echo "  3. Copia .graphiti.json a cada proyecto (del template en config/)."
echo "  4. En CLAUDE.md de cada proyecto añade la sección ## Memory."
echo "  5. En Claude Code verifica: /mcp list"
echo ""
