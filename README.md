# ClaudeSetup

Setup completo de Claude Code con memoria persistente, grafos de conocimiento y skills agénticos, diseñado para funcionar en 2-3 laptops con múltiples cuentas de Claude, sincronizado en OneDrive.

> **Antes de tocar nada:** lee [`docs/arquitectura-memoria/07-HALLAZGOS-CRITICOS-REFERENCIA-RAPIDA.md`](./docs/arquitectura-memoria/07-HALLAZGOS-CRITICOS-REFERENCIA-RAPIDA.md). Son 10 datos que cambian decisiones de arquitectura y evitan errores costosos.

---

## ¿Qué hay en este repo?

```
/docs/          sustento técnico de cada decisión de arquitectura (8 documentos)
/setup/         archivos de configuración listos para usar
/_archive/      análisis previo de referencia histórica
README.md       este archivo — guía de instalación
```

**La arquitectura en una línea:**

```
Graphify (grafo del código) + Obsidian (memoria de sesiones) + Graphiti/FalkorDB (memoria temporal) + Superpowers (metodología)
```

Todo sincronizado via OneDrive para los `.md` del vault y git dotfiles para la config de Claude Code.

---

## Prerrequisitos (cualquier laptop, cualquier escenario)

Instala esto antes de seguir cualquiera de los dos caminos:

| Herramienta        | Instalación                                                                          | Para qué            |
| ------------------ | ------------------------------------------------------------------------------------ | ------------------- |
| **Claude Code**    | `npm install -g @anthropic-ai/claude-code`                                           | El agente principal |
| **Docker Desktop** | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop) | Graphiti + FalkorDB |
| **Obsidian**       | [obsidian.md](https://obsidian.md)                                                   | Vault de memoria    |
| **OneDrive**       | Ya instalado en Windows; [onedrive.com](https://onedrive.com) en macOS/Linux         | Sync del vault      |
| **uv** (Python)    | `curl -LsSf https://astral.sh/uv/install.sh \| sh`                                   | Instalar Graphify   |

Verifica que OneDrive esté sincronizado y que la carpeta `DevSetup/` exista localmente antes de continuar.

---

## Camino A — Primera laptop (setup desde cero)

Sigue este orden. Cada fase tiene impacto inmediato y prepara la siguiente.

### Fase 0 — Impacto en 15 minutos

```bash
# 1. Autenticarte en Claude Code
claude auth

# 2. Instalar Superpowers (metodología de desarrollo agéntico)
claude code
/plugin install superpowers@claude-plugins-official

# 3. Instalar Context7 (documentación actualizada de librerías)
claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@latest

# 4. Instalar Graphify (grafo del codebase, 0 tokens propios)
uv tool install graphifyy
graphify install   # registra el skill en Claude Code
```

En este punto Claude Code ya tiene metodología mejorada, docs actualizadas de tus librerías y capacidad de grafo del codebase. Abre cualquier proyecto y prueba `/graphify .`

### Fase 1 — Memoria de sesiones con Obsidian (~30 min)

**Crear el vault:**

1. Abre Obsidian → "Create new vault"
2. Nombre: `ObsidianVault`
3. Ubicación: `~/OneDrive/DevSetup/ObsidianVault/`

**Crear la estructura base de carpetas** (dentro del vault):

```
00-Inbox/
10-Projects/
20-Areas/
  dev-conventions/
30-Resources/
40-Archive/
brain/
daily/
templates/
```

**Instalar plugins esenciales** (Settings → Community plugins → Browse):

| Plugin                | Por qué                                                       |
| --------------------- | ------------------------------------------------------------- |
| **Obsidian Git**      | Auto-commit cada 10 min — protege contra corrupción de Claude |
| **Templater**         | Frontmatter automático con fecha y metadata                   |
| **Dataview**          | Consultas por proyecto, estado, fecha                         |
| **Periodic Notes**    | Daily notes para journal de sesiones                          |
| **Smart Connections** | Búsqueda semántica dentro del vault                           |

**Configurar Obsidian Git** (Settings → Obsidian Git):

- Auto pull interval: `10` minutos
- Auto push interval: `10` minutos
- Commit message: `auto: {{date}} {{hostname}}`

**Conectar Obsidian con Claude Code:**

```bash
claude mcp add obsidian-vault -s user -- \
  npx -y @modelcontextprotocol/server-filesystem \
  ~/OneDrive/DevSetup/ObsidianVault
```

**Para cada proyecto activo**, crea `10-Projects/[nombre-proyecto]/_PROJECT.md` con este frontmatter:

```yaml
---
title: Nombre del Proyecto
stack: [react, flutter, python, cpp]
status: active
created: YYYY-MM-DD
---
```

### Fase 2 — Multi-dispositivo (~20 min)

Esto prepara el repo para que la próxima laptop tarde < 15 minutos en configurarse.

**Crear el repo de dotfiles** (privado en GitHub):

```bash
mkdir ~/OneDrive/DevSetup/claude-dotfiles
cd ~/OneDrive/DevSetup/claude-dotfiles
git init
git remote add origin git@github.com:TU_USUARIO/claude-dotfiles.git
```

**Copiar la config portátil de Claude Code al repo:**

```bash
cp ~/.claude/CLAUDE.md .
cp ~/.claude/settings.json .
cp -r ~/.claude/agents ./agents 2>/dev/null || true
cp -r ~/.claude/skills ./skills 2>/dev/null || true
cp -r ~/.claude/rules ./rules 2>/dev/null || true
```

Crear `.gitignore` en el repo de dotfiles:

```gitignore
# Ignorar todo por defecto
*
!.gitignore
!CLAUDE.md
!settings.json
!agents/
!agents/**
!skills/
!skills/**
!rules/
!rules/**
!graphiti/
!graphiti/**
```

**Copiar los archivos de setup de este repo** al repo de dotfiles:

```bash
cp -r setup/ ./graphiti
```

**Primer commit:**

```bash
git add .
git commit -m "feat: initial claude code setup"
git push -u origin main
```

### Fase 3 — Graphiti + FalkorDB con Docker (~1-2 horas)

> Solo si necesitas memoria temporal (hechos que cambian con el tiempo entre sesiones). Si no estás seguro, salta esta fase y vuelve cuando la necesites.

**Configurar el entorno:**

```bash
# Crear directorio de trabajo (fuera de OneDrive para los datos vivos)
mkdir -p ~/graphiti-docker
cp setup/docker/docker-compose.yml ~/graphiti-docker/
cp setup/docker/.env.example ~/graphiti-docker/.env
```

**Editar `~/graphiti-docker/.env`** con tus valores reales:

```env
# Datos en disco local (NO en OneDrive — ver docs/arquitectura-memoria/04 para el motivo)
FALKORDB_DATA_PATH=./data
CONFIG_PATH=./config

# Usar OpenAI para extracción de entidades (más estable que Anthropic)
LLM_PROVIDER=openai
OPENAI_API_KEY=sk-...

MODEL_NAME=gpt-4.1-mini
SMALL_MODEL_NAME=gpt-4.1-nano
SEMAPHORE_LIMIT=3
```

**Copiar la config del MCP server:**

```bash
mkdir -p ~/graphiti-docker/config
cp setup/config/config.yaml ~/graphiti-docker/config/
```

**Levantar los containers:**

```bash
cd ~/graphiti-docker
docker compose up -d

# Verificar que todo arrancó
docker exec graphiti-falkordb redis-cli ping   # debe responder: PONG
# UI del grafo disponible en: http://localhost:3000
# MCP endpoint en: http://localhost:8000/mcp/
```

**Conectar con Claude Code:**

```bash
claude mcp add --transport http graphiti-memory \
  http://localhost:8000/mcp/ -s user
```

**Configurar backup automático a OneDrive:**

macOS/Linux — añadir al crontab (`crontab -e`):

```
0 */4 * * * ONEDRIVE_PATH=$HOME/OneDrive bash ~/graphiti-docker/backup-graph.sh
```

Windows — ejecutar en PowerShell como admin:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-File `"$HOME\graphiti-docker\backup-graph.ps1`""
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 4) -Once -At (Get-Date)
Register-ScheduledTask -TaskName "GraphitiBackup" -Action $action -Trigger $trigger
```

**Para cada proyecto**, copia el template de config:

```bash
cp setup/config/graphiti-project-template.json /ruta/al/proyecto/.graphiti.json
# Edita .graphiti.json: cambia "MI-PROYECTO" por el nombre real del proyecto
```

### Fase 4 — Por stack (ongoing)

**C++ — inteligencia de símbolos:**

```bash
# En Claude Code:
/plugin install clangd-lsp@claude-plugins-official

# En cada proyecto C++, generar compile_commands.json:
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
```

**React/Next.js — verificación visual:**

```bash
claude mcp add playwright -s user -- npx -y @playwright/mcp@latest
```

**Todos los stacks — formateo automático:**

Añadir en `~/.claude/settings.json` bajo `hooks`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write \"$CLAUDE_TOOL_INPUT_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

**Multi-cuenta Claude** (si tienes cuenta personal y de trabajo):

```bash
# macOS/Linux — añadir a ~/.bashrc o ~/.zshrc:
alias claude-personal='CLAUDE_CONFIG_DIR=~/.claude-personal command claude'
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work command claude'

# Windows — añadir a $PROFILE de PowerShell:
function claude-personal { $env:CLAUDE_CONFIG_DIR="$HOME\.claude-personal"; claude @args }
function claude-work { $env:CLAUDE_CONFIG_DIR="$HOME\.claude-work"; claude @args }
```

---

## Camino B — Laptop nueva (ya tienes el setup en otra máquina)

**Prerrequisito**: OneDrive sincronizado con `DevSetup/` visible localmente.

### Opción rápida — Script automático

```bash
# macOS/Linux:
bash setup/scripts/setup-new-machine.sh ~/OneDrive

# Windows (PowerShell como admin):
.\setup\scripts\setup-new-machine.ps1 -OneDrivePath "$env:USERPROFILE\OneDrive"
```

El script hace automáticamente: instala MCPs, copia dotfiles a `~/.claude/`, detecta el backup `.rdb` más reciente de FalkorDB, pregunta si restaurar, levanta Docker y configura el cron de backup.

**Después del script** (solo esto es manual):

```bash
# 1. Editar el .env con tus API keys (el script las deja vacías por seguridad)
nano ~/graphiti-docker/.env    # o code, vim, etc.

# 2. Reiniciar el MCP server para que tome las keys
cd ~/graphiti-docker
docker compose restart graphiti-mcp

# 3. Instalar Obsidian y apuntarlo al vault existente
# Abrir Obsidian → "Open folder as vault" → ~/OneDrive/DevSetup/ObsidianVault/

# 4. Instalar Claude Code si no está
npm install -g @anthropic-ai/claude-code
claude auth
```

### Opción manual — paso a paso

Si prefieres hacerlo sin el script o el script falla en algún paso:

**1. Clonar dotfiles y copiar config:**

```bash
cd ~/OneDrive/DevSetup/claude-dotfiles
cp CLAUDE.md ~/.claude/
cp settings.json ~/.claude/
cp -r agents ~/.claude/ 2>/dev/null || true
cp -r skills ~/.claude/ 2>/dev/null || true
cp -r rules ~/.claude/ 2>/dev/null || true
```

**2. Reinstalar plugins y MCPs:**

```bash
# En Claude Code:
/plugin install superpowers@claude-plugins-official
/plugin install clangd-lsp@claude-plugins-official  # si usas C++

# MCPs:
claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@latest
claude mcp add obsidian-vault -s user -- \
  npx -y @modelcontextprotocol/server-filesystem \
  ~/OneDrive/DevSetup/ObsidianVault
```

**3. Restaurar el grafo de Graphiti desde el último backup:**

```bash
# Ver backups disponibles en OneDrive:
ls ~/OneDrive/DevSetup/graphiti-data/backups/

# Copiar el más reciente al directorio de datos local:
mkdir -p ~/graphiti-docker/data
cp ~/OneDrive/DevSetup/graphiti-data/backups/graphiti_YYYYMMDD_HHMMSS.rdb \
   ~/graphiti-docker/data/dump.rdb

# Levantar Docker (FalkorDB cargará el grafo desde dump.rdb):
cd ~/graphiti-docker
docker compose up -d

# Conectar con Claude Code:
claude mcp add --transport http graphiti-memory \
  http://localhost:8000/mcp/ -s user
```

**4. Abrir Obsidian:**

- Abrir Obsidian → "Open folder as vault"
- Seleccionar: `~/OneDrive/DevSetup/ObsidianVault/`
- Los plugins se reinstalan automáticamente desde la config en `.obsidian/`

**5. Reinstalar Graphify:**

```bash
uv tool install graphifyy
graphify install
```

---

## Verificar que todo funciona

```bash
# Claude Code y MCPs
claude mcp list
# Debe mostrar: context7, obsidian-vault, graphiti-memory (y otros que hayas agregado)

# FalkorDB
docker exec graphiti-falkordb redis-cli ping
# Debe responder: PONG

# Grafo en UI
open http://localhost:3000   # macOS
# Windows: abrir browser en http://localhost:3000

# Graphify en un proyecto
cd /ruta/a/un/proyecto
/graphify .
```

---

## Protocolo al cambiar de laptop

> Seguir este orden evita el único riesgo real de pérdida de datos: un backup desactualizado.

```
En la laptop que vas a dejar:
  1. docker compose stop graphiti-falkordb   ← fuerza snapshot final del grafo
  2. bash ~/graphiti-docker/backup-graph.sh  ← copia .rdb a OneDrive
  3. Esperar que OneDrive diga "Actualizado" (ícono sin conflictos)

En la laptop nueva:
  4. Verificar que OneDrive ya sincronizó (el .rdb nuevo debe estar visible)
  5. Seguir Camino B — Opción rápida o manual
```

---

## Estructura de archivos en OneDrive (resultado final)

```
OneDrive/
└── DevSetup/
    ├── claude-dotfiles/          ← repo git con config portátil de Claude Code
    │   ├── CLAUDE.md
    │   ├── settings.json
    │   ├── agents/
    │   ├── skills/
    │   ├── rules/
    │   └── graphiti/             ← docker-compose, config.yaml, scripts
    ├── ObsidianVault/            ← vault completo (sincroniza perfectamente)
    │   ├── .obsidian/
    │   ├── 00-Inbox/
    │   ├── 10-Projects/
    │   ├── brain/
    │   └── daily/
    └── graphiti-data/
        └── backups/              ← snapshots .rdb con timestamp (datos del grafo)
```

Los datos vivos de FalkorDB van en **disco local** (`~/graphiti-docker/data/`), no en OneDrive. Solo los backups `.rdb` van a OneDrive. Ver [`docs/arquitectura-memoria/04-ONEDRIVE-SINCRONIZACION-MULTI-LAPTOP.md`](./docs/arquitectura-memoria/04-ONEDRIVE-SINCRONIZACION-MULTI-LAPTOP.md) para el detalle de por qué.

---

## Documentación de referencia

| Documento                                                                                              | Cuándo leerlo                         |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| [`docs/arquitectura-memoria/00-INDICE-Y-RESUMEN-EJECUTIVO.md`](./docs/arquitectura-memoria/00-INDICE-Y-RESUMEN-EJECUTIVO.md)                     | Visión general de la arquitectura     |
| [`docs/arquitectura-memoria/07-HALLAZGOS-CRITICOS-REFERENCIA-RAPIDA.md`](./docs/arquitectura-memoria/07-HALLAZGOS-CRITICOS-REFERENCIA-RAPIDA.md) | Antes de cualquier decisión de config |
| [`docs/arquitectura-memoria/01-OBSIDIAN-MEMORIA-EXTERNA.md`](./docs/arquitectura-memoria/01-OBSIDIAN-MEMORIA-EXTERNA.md)                         | Setup del vault en detalle            |
| [`docs/arquitectura-memoria/02-GRAFOS-VS-MARKDOWN.md`](./docs/arquitectura-memoria/02-GRAFOS-VS-MARKDOWN.md)                                     | Por qué esta arquitectura y no otra   |
| [`docs/arquitectura-memoria/03-GRAPHITI-FALKORDB-MEMORIA-TEMPORAL.md`](./docs/arquitectura-memoria/03-GRAPHITI-FALKORDB-MEMORIA-TEMPORAL.md)     | Graphiti a fondo                      |
| [`docs/arquitectura-memoria/04-ONEDRIVE-SINCRONIZACION-MULTI-LAPTOP.md`](./docs/arquitectura-memoria/04-ONEDRIVE-SINCRONIZACION-MULTI-LAPTOP.md) | Estrategias A/B/C de sync             |
| [`docs/arquitectura-memoria/05-SKILLS-FRAMEWORKS-AGENTICOS.md`](./docs/arquitectura-memoria/05-SKILLS-FRAMEWORKS-AGENTICOS.md)                   | MCPs, Superpowers, subagents          |
| [`docs/arquitectura-memoria/06-ARQUITECTURA-FINAL-RECOMENDADA.md`](./docs/arquitectura-memoria/06-ARQUITECTURA-FINAL-RECOMENDADA.md)             | Plan de implementación por fases      |
