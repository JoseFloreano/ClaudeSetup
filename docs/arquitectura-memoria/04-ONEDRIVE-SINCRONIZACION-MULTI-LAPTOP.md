# OneDrive: Estrategias de Sincronización Multi-Laptop
## Hallazgos críticos, riesgos documentados y protocolos recomendados

---

## 1. El problema raíz: no todo se sincroniza igual

OneDrive es una excelente solución para documentos, fotos y archivos de Office. Para configuración de desarrollo, código y bases de datos, tiene limitaciones específicas que deben conocerse antes de diseñar cualquier arquitectura.

### Lo que OneDrive maneja bien

| Tipo de dato | Comportamiento |
|--------------|----------------|
| Archivos `.md` (vault Obsidian) | ✅ Sincroniza perfectamente — texto plano, sin locks |
| Archivos de configuración JSON/YAML | ✅ Sin problemas |
| Scripts shell/PowerShell | ✅ Sin problemas |
| Archivos de dotfiles (`.claude/settings.json`) | ✅ Con caveats de path |
| Documentos de Office | ✅ Diseñado para esto |

### Lo que OneDrive maneja mal

| Tipo de dato | Problema |
|--------------|----------|
| Symlinks / Junctions (Windows) | ❌ Microsoft confirma: no soporta nativamente symlinks. Sincroniza el archivo real, no el enlace |
| Archivos con locks activos (DB files) | ❌ Puede interrumpir escrituras mid-operation → corrupción |
| `node_modules/` | ❌ Miles de archivos pequeños → sync lentísima, quota agotada |
| Archivos binarios grandes que cambian frecuentemente | ⚠️ Funciona, pero lento y consume quota |
| Repositorios git (el directorio `.git/`) | ⚠️ Funciona pero innecesario; los objetos git son muchos archivos pequeños |

### El hallazgo crítico sobre FalkorDB + OneDrive

FalkorDB (basado en Redis) opera con dos archivos de persistencia abiertos permanentemente mientras el container corre:
- `dump.rdb` — snapshot RDB, se sobreescribe periódicamente
- `appendonly.aof` — Write-Ahead Log, se escribe en cada operación

OneDrive detecta estos archivos como "archivos abiertos por otra aplicación" y puede:
1. Intentar subir una versión parcial durante una escritura
2. Bloquear la sync esperando que el lock se libere
3. En casos extremos, corromper el archivo al forzar una sincronización

**Esto no es un bug de OneDrive — es comportamiento correcto para archivos de base de datos que no deben sincronizarse con una herramienta de sync de documentos.**

---

## 2. Las tres estrategias de sincronización

### Estrategia A — Datos locales + backups periódicos a OneDrive (RECOMENDADA)

```
Laptop 1:
  Docker Volume → disco local (/var/lib/falkordb/data)
  Cron cada 4h → BGSAVE + cp dump.rdb → OneDrive/graphiti-data/backups/

Laptop 2:
  setup-new-machine.sh detecta el .rdb más reciente en OneDrive
  → restaura el grafo desde el snapshot
  → inicia FalkorDB con los datos restaurados
```

**Flujo al cambiar de laptop:**
```bash
# En laptop actual, antes de cerrar:
docker compose stop graphiti-falkordb  # fuerza BGSAVE final
./scripts/backup-graph.sh              # copia a OneDrive
# Esperar que OneDrive sincronice (ícono sin conflictos)

# En nueva laptop:
./scripts/setup-new-machine.sh
# El script detecta el .rdb más reciente y pregunta si restaurar
```

**Trade-offs:**
- ✅ Cero riesgo de corrupción
- ✅ FalkorDB en disco local → máximo rendimiento
- ✅ OneDrive sin conflictos (solo recibe snapshots terminados)
- ⚠️ El grafo entre laptops tiene un desfase de hasta 4 horas
- ⚠️ Requiere protocolo consciente al cambiar de máquina

### Estrategia B — Datos directamente en OneDrive (un laptop a la vez)

```yaml
# docker-compose.yml
volumes:
  - ${FALKORDB_DATA_PATH}:/var/lib/falkordb/data
# donde FALKORDB_DATA_PATH apunta a OneDrive
```

**Protocolo obligatorio:**
```bash
# ANTES de cambiar de laptop (SIEMPRE):
docker compose stop graphiti-falkordb
# Verificar que OneDrive dice "Actualizado" (no "Cargando")
# Solo entonces abrir el container en la otra laptop
```

**Trade-offs:**
- ✅ Grafo siempre al día entre laptops
- ❌ Riesgo de corrupción si se olvida el protocolo
- ❌ Rendimiento inferior (I/O a través de OneDrive filesystem layer)
- ❌ Requiere disciplina estricta del protocolo

### Estrategia C — FalkorDB Cloud (más limpia para multi-laptop)

```yaml
# docker-compose.yml — sin volumen local, conexión a cloud
environment:
  - FALKORDB_HOST=tu-instancia.falkordb.cloud
  - FALKORDB_PORT=6379
  - FALKORDB_USER=default
  - FALKORDB_PASSWORD=${FALKORDB_CLOUD_PASSWORD}
# No se necesita el servicio falkordb local
```

**Cuándo usar:**
- Si cambias de laptop múltiples veces al día
- Si el protocolo de la Estrategia B es demasiado frágil para tu flujo
- Si el presupuesto permite el costo del servicio managed

**Trade-offs:**
- ✅ Grafo disponible desde cualquier laptop inmediatamente
- ✅ Sin gestión de Docker para la DB
- ✅ Sin riesgo de corrupción
- ❌ Costo mensual
- ❌ Requiere internet para escritura (lectura también online)

---

## 3. Sincronización de configuración de Claude Code

### El problema del `~/.claude/` directory

`~/.claude/` contiene una mezcla de datos que tienen comportamientos diferentes:

```
~/.claude/
├── CLAUDE.md              ← portátil — sincronizar
├── settings.json          ← portátil — sincronizar
├── commands/              ← portátil — sincronizar
├── agents/                ← portátil — sincronizar
├── skills/                ← portátil — sincronizar
├── rules/                 ← portátil — sincronizar
├── .credentials.json      ← NUNCA sincronizar (contiene tokens de API)
├── history.jsonl          ← no sincronizar (historial local de la máquina)
├── projects/              ← no sincronizar (paths absolutos de máquina)
├── file-history/          ← no sincronizar (caché de archivos)
├── cache/                 ← no sincronizar
├── sessions/              ← no sincronizar
└── telemetry/             ← no sincronizar
```

### La solución: git con allowlist explícita

```gitignore
# .gitignore en el repo claude-dotfiles/
# Ignorar todo por defecto, solo incluir lo que queremos sincronizar
*
!.gitignore
!CLAUDE.md
!settings.json
!commands/
!commands/**
!agents/
!agents/**
!skills/
!skills/**
!rules/
!rules/**
```

El repo `claude-dotfiles` en OneDrive o GitHub privado contiene solo la configuración portátil. En cada laptop nueva, un script de bootstrap **copia** (no symlink) los archivos al `~/.claude/` local.

### Por qué copiar en vez de symlink

Microsoft documenta que OneDrive no soporta symlinks de forma confiable en Windows. Si el dotfiles repo está en OneDrive y se crean symlinks desde `~/.claude/` apuntando a OneDrive, en el mejor caso funcionan pero no se detectan cambios correctamente; en el peor caso, OneDrive sube el contenido del symlink destino (potencialmente gigabytes de archivos).

**La solución es simple**: copiar los archivos y usar git para detectar y propagar cambios manualmente.

### Multi-cuenta Claude con `CLAUDE_CONFIG_DIR`

Para manejar múltiples cuentas de Claude (personal, trabajo, cliente), la solución oficial de Anthropic es la variable de entorno `CLAUDE_CONFIG_DIR`:

```bash
# macOS / Linux
alias claude-personal='CLAUDE_CONFIG_DIR=~/.claude-personal command claude'
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work command claude'
alias claude-cliente='CLAUDE_CONFIG_DIR=~/.claude-cliente command claude'
```

```powershell
# Windows PowerShell
function claude-personal { $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-personal"; claude @args; Remove-Item Env:\CLAUDE_CONFIG_DIR }
function claude-work { $env:CLAUDE_CONFIG_DIR = "$HOME\.claude-work"; claude @args; Remove-Item Env:\CLAUDE_CONFIG_DIR }
```

Cada directorio tiene sus propias credenciales, settings e historial. El vault de Obsidian y el grafo de Graphiti pueden ser **compartidos** entre cuentas (son datos del proyecto, no de la cuenta).

### El bug de `~/.claude.json` en Windows

**Hallazgo documentado**: En Windows, Claude Code guarda estado adicional en `%USERPROFILE%\.claude.json` (fuera del `~/.claude/` directory). Este archivo es compartido entre todas las instancias y se convierte en punto de conflicto cuando se usan múltiples `CLAUDE_CONFIG_DIR`.

La solución documentada (Josh Grossman, 2026) es dar a cada instancia un `$env:USERPROFILE` falso con un directorio separado, más symlinks para los binarios. Es una configuración avanzada que solo vale si se necesitan múltiples instancias simultáneas en Windows.

---

## 4. El vault de Obsidian: configuración óptima en OneDrive

### Qué sincronizar

```
OneDrive/DevSetup/ObsidianVault/
├── *.md                ✅ El vault completo
├── .obsidian/
│   ├── plugins/        ✅ Config de plugins (lenta al principio)
│   ├── themes/         ✅ Temas
│   ├── snippets/       ✅ CSS snippets
│   ├── app.json        ✅ Config general
│   ├── hotkeys.json    ✅ Atajos de teclado
│   ├── community-plugins.json  ✅ Lista de plugins
│   └── workspace.json  ❌ EXCLUIR — estado de ventanas por máquina
```

### Exclusiones necesarias en `.gitignore` del vault

```gitignore
# Caché — se regenera automáticamente
.obsidian/cache
.obsidian/.pdf/
.obsidian/plugins/smart-connections/embeddings/
.obsidian/plugins/smart-connections/cache/

# Estado de ventana — específico de cada máquina
.obsidian/workspace.json
.obsidian/workspace-mobile.json
```

### Conflictos de sync: cómo evitarlos

El problema más común con Obsidian + OneDrive es la creación de archivos `[nota] - conflicto FECHA.md` cuando dos laptops editan la misma nota simultáneamente. Para un desarrollador que trabaja en una laptop a la vez, esto es raro pero posible.

**Protocolo de prevención:**
1. Obsidian Git con auto-pull al abrir Obsidian
2. Auto-push al cerrar Obsidian
3. Si OneDrive muestra conflictos: resolver manualmente y conservar la versión más reciente

Alternativa más robusta: **Obsidian Sync** (servicio oficial de Obsidian, ~$8/mes) que maneja conflictos de forma nativa, o **Obsidian Git** con un repositorio git separado del vault de OneDrive.

---

## 5. Estructura completa en OneDrive

Esta es la estructura recomendada que resulta de toda la investigación:

```
OneDrive/
└── DevSetup/
    │
    ├── claude-dotfiles/          ← repo git (privado en GitHub)
    │   ├── CLAUDE.md             ← global, todos los proyectos
    │   ├── settings.json
    │   ├── commands/
    │   ├── agents/
    │   ├── skills/
    │   ├── rules/
    │   ├── graphiti/             ← configs de Graphiti
    │   │   ├── docker-compose.yml
    │   │   ├── config.yaml
    │   │   └── scripts/
    │   ├── claude-md-templates/  ← plantillas CLAUDE.md por stack
    │   │   ├── react-nextjs.md
    │   │   ├── flutter.md
    │   │   ├── python.md
    │   │   └── cpp-cmake.md
    │   └── bootstrap/
    │       ├── setup.sh          ← Linux/macOS
    │       └── setup.ps1         ← Windows
    │
    ├── ObsidianVault/            ← vault Obsidian (sincroniza perfectamente)
    │   ├── .obsidian/
    │   ├── 00-Inbox/
    │   ├── 10-Projects/
    │   ├── 20-Areas/
    │   ├── 30-Resources/
    │   ├── 40-Archive/
    │   ├── brain/
    │   ├── daily/
    │   └── templates/
    │
    ├── graphiti-docker/          ← directorio de trabajo Docker
    │   ├── docker-compose.yml    ← copiado desde claude-dotfiles
    │   └── .env                  ← API keys (NUNCA en git)
    │
    └── graphiti-data/            ← datos del grafo (si usas Estrategia B)
        ├── falkordb/             ← ADVERTENCIA: ver sección de riesgos
        ├── backups/              ← snapshots .rdb con timestamp (Estrategia A)
        └── config/
            └── config.yaml
```

**Lo que no está en OneDrive:**
- Código fuente de proyectos (en disco local, versionado en GitHub/GitLab)
- `node_modules/`, `.dart_tool/`, `__pycache__/`, build artifacts de C++
- Credenciales de Claude (`.credentials.json`)
- Caché de cualquier herramienta

---

## 6. Tabla resumen de decisiones

| Dato | OneDrive | Git dotfiles | Disco local | Nunca sincronizar |
|------|----------|--------------|-------------|-------------------|
| Vault Obsidian (.md) | ✅ | — | — | — |
| CLAUDE.md global | ✅ | ✅ | — | — |
| settings.json Claude | ✅ | ✅ | — | — |
| API keys (.env) | — | — | — | ✅ |
| .credentials.json | — | — | — | ✅ |
| FalkorDB data (Estrategia A) | backups .rdb | — | ✅ datos live | — |
| FalkorDB data (Estrategia B) | ✅ con caveats | — | — | — |
| Código fuente | — | GitHub | ✅ | — |
| node_modules / build | — | — | ✅ | — |
| historial Claude Code | — | — | ✅ | — |

---

*Siguiente: [Skills y Frameworks Agénticos](./05-SKILLS-FRAMEWORKS-AGENTICOS.md)*
