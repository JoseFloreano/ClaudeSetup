# Setup óptimo de Claude Code con memoria externa (Obsidian), skills agénticos y sincronización multi-dispositivo/multi-cuenta vía OneDrive

## TL;DR

- **Arquitectura recomendada:** instala los plugins/skills agénticos vía el marketplace oficial (`obra/superpowers`), conecta tu vault de Obsidian como memoria persistente con el plugin `iansinnott/obsidian-claude-code-mcp` (auto-descubre por WebSocket en puerto 22360) o el filesystem-MCP, versiona tu `~/.claude` con **git** (no con symlinks dentro de OneDrive, que NO soporta symlinks/junctions de forma fiable), y separa cuentas con `CLAUDE_CONFIG_DIR`.
- **No sincronices todo `~/.claude` por OneDrive a ciegas:** el directorio mezcla config portable (CLAUDE.md, settings.json, skills, agents, commands) con estado de máquina (credenciales, caché, history.jsonl, projects/, file-history). Sincroniza solo la config con un allowlist; deja credenciales y caché fuera. OneDrive sirve perfectamente para el **vault de Obsidian** (archivos .md planos), que es tu memoria compartida real entre dispositivos.
- **Stack:** Superpowers (metodología TDD/brainstorm) + MCPs esenciales (filesystem, github, context7, playwright, sequential-thinking, memory/knowledge-graph, obsidian) + clangd-LSP para C++ + hooks de formato/seguridad + subagents por lenguaje.

## Key Findings

### 1. Frameworks y Skills agénticos

**obra/Superpowers** es el framework de referencia, creado por **Jesse "Obra" Vincent (ex-Anthropic)** y el equipo de Prime Radiant. Es "a complete software development methodology for your coding agents, built on top of a set of composable skills" (una metodología completa de desarrollo de software para agentes de codificación, construida sobre skills componibles). El repo `obra/superpowers` acumula del orden de ~216k estrellas a junio de 2026. Instalación en Claude Code (2 comandos):

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

**Contenido real:** el repositorio incluye **14 skills** (cada una un único `SKILL.md` con frontmatter YAML), no "20+" como se repite en algunos blogs. Se activan automáticamente cuando son relevantes; las cinco de mayor valor son `verification-before-completion`, `subagent-driven-development`, `test-driven-development`, `brainstorming` y `writing-plans`. Otras incluyen `using-git-worktrees` y `systematic-debugging`. Aporta los comandos `/superpowers:brainstorm`, `/write-plan`, `/execute-plan`. Es **zero-dependency** por diseño. También está disponible en el **marketplace oficial de Anthropic desde el 15 de enero de 2026** (`/plugin install superpowers@claude-plugins-official`). La telemetría se limita al logo de la feature visual de brainstorming; el README confirma: "To disable this, set the environment variable `SUPERPOWERS_DISABLE_TELEMETRY` to any true value. Superpowers also honors Claude Code's `DISABLE_TELEMETRY` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` opt-outs."

**Eigenwise/atomic-agents** es algo distinto: NO es un plugin de Claude Code, sino un framework Python/Pydantic ("building AI agents, atomically") para construir pipelines agénticos propios, basado en Instructor + Pydantic. Un agente se compone de System Prompt, Input/Output Schema (Pydantic), History y Context Providers. Se instala con `git clone` + `uv sync`. Soporta múltiples proveedores (incluido Anthropic) vía Instructor. **Sí existe** un plugin de Claude Code _para desarrollar_ apps de Atomic Agents (brainblend-ai-atomic-agents) con agentes especializados de diseño de schema, arquitectura y revisión. Conclusión: Superpowers y atomic-agents resuelven problemas diferentes — Superpowers mejora _cómo Claude Code codifica_; atomic-agents es para _construir tus propios agentes en Python_.

**Otros frameworks/colecciones relevantes:**

- `wshobson/agents` — marketplace multi-harness: 84 plugins, 192 agentes, 156 skills, 102 comandos, generados desde una sola fuente Markdown para Claude Code/Codex/Cursor/OpenCode/Copilot/Gemini.
- `VoltAgent/awesome-claude-code-subagents` — 100+ subagentes especializados (incluye `flutter-expert`, `cpp-pro`, `python-expert`).
- `alirezarezvani/claude-skills` — 337 skills, 30+ agentes, 70+ comandos, 579 scripts Python stdlib-only.
- `jeremylongshore/claude-code-plugins-plus-skills` — marketplace con 425 plugins / 2.810 skills / 200 agentes.
- `disler/claude-code-hooks-mastery` — referencia de hooks + sub-agents + meta-agent.
- `MuhammadUsmanGM/claude-code-best-practices` — 11 templates CLAUDE.md (incluye React, Python, Flutter, Next.js).

### 2. Conceptos centrales de Claude Code (modelo mental)

Hay 7 categorías de features: **CLAUDE.md, Skills (que ahora absorben los antiguos Commands), Subagents, Agent Teams, Plugins, Hooks y MCP Servers**. Distinción clave:

- **Skills**: instrucciones modulares (SKILL.md con frontmatter YAML); cargan por _progressive disclosure_ (Claude solo carga lo que necesita). Pueden auto-invocarse o llamarse con `/skill-name`. `SkillTool` inyecta en el contexto actual.
- **Subagents**: instancia Claude separada con su propio contexto; devuelve solo el resultado. `AgentTool` genera contexto aislado. Built-in: Explore (read-only, rápido), Plan (research), general-purpose. Buenos para paralelizar y proteger la ventana de contexto.
- **Agent Teams**: subagentes que coordinan entre sí (comparten task list y se mensajean).
- **Plugins**: contenedor empaquetable que agrupa skills + hooks + subagents + MCP servers; namespaced (`plugin:skill`).
- **Hooks**: scripts de shell deterministas en eventos del ciclo de vida.
- **MCP**: protocolo para conectar herramientas externas.

Nota arquitectónica útil (del análisis VILA-Lab/Dive-into-Claude-Code): las instrucciones de CLAUDE.md se entregan como _user context_ (cumplimiento probabilístico), no como system prompt (determinista). La memoria es basada en archivos (sin vector DB), inspeccionable y versionable.

### 3. Obsidian como memoria externa

Hay tres caminos para conectar Obsidian con Claude Code:

**A) MCP servers (recomendado para memoria persistente bidireccional):**

- `iansinnott/obsidian-claude-code-mcp` — plugin de Obsidian que corre un servidor MCP. Claude Code auto-descubre y se conecta por WebSocket en el **puerto 22360** (configurable; cada vault necesita puerto único). Usa deliberadamente el protocolo legacy "HTTP with SSE" (2024-11-05) por compatibilidad. Para Claude Desktop usa `mcp-remote`:

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:22360/sse"],
      "env": {}
    }
  }
}
```

- `MarkusPfundstein/mcp-obsidian` — **2,8k estrellas y 344 forks** (junio 2026); basado en REST API, requiere el plugin community "Local REST API" de coddingtonbear. Expone **7 herramientas**: `list_files_in_vault`, `list_files_in_dir`, `get_file_contents`, `search`, `patch_content`, `append_content`, `delete_file`. Se corre con `uvx mcp-obsidian`.
- `cyanheads/obsidian-mcp-server` — alternativa Node más rica (`npx obsidian-mcp-server`), edita secciones, tags y frontmatter.
- **Filesystem MCP** (sin plugin) — como un vault es solo una carpeta de .md, apuntar el filesystem-MCP a la carpeta del vault funciona directamente; es lo más simple y seguro (limita el acceso a ese directorio).

**B) Symlinks** — `ln -s ~/vault/notes ./docs` para dar a Claude Code acceso de lectura. Simple pero NO portable vía OneDrive en Windows.

**C) Plugins de Obsidian con IA embebida** — Claudian (Claude Code en la sidebar), Smart Connections (búsqueda semántica), Copilot for Obsidian.

**⚠️ Riesgo crítico documentado:** corrupción del vault. Cuando Claude tiene acceso de escritura "puede sobrescribir notas si no tienes cuidado". El fix obligatorio es **git: cada cambio commiteado, sin excepciones** (usa el plugin Obsidian Git con auto-commit). Otro problema reportado: duplicación de memorias ("el mismo tema en 10 sesiones produce 10 entradas casi idénticas") → añade un paso "search-before-save".

**Plugins de Obsidian recomendados para un vault de desarrollo:** Dataview (consulta el vault como base de datos vía frontmatter/inline fields; o el nuevo core plugin **Bases** con GUI visual), Templater (motor de plantillas con JS), Tasks, QuickAdd, Periodic Notes + Calendar (daily/weekly notes), **Obsidian Git** (versionado/backup automático), Linter (formato consistente), Smart Connections (búsqueda semántica IA). Mantén el stack ligero: bajo 20 plugins no hay impacto perceptible; 40+ genera lentitud y conflictos.

**Patrón de vault para software con IA:** estructura tipo PARA o IPARAG (Inbox/Projects/Areas/Resources/Archives), con daily notes, project notes (ADRs — Architecture Decision Records), templates, y un "North Star". El proyecto `breferrari/obsidian-mind` da un vault completo donde "todo el conocimiento durable vive en `brain/` topic notes (git-tracked, navegables en Obsidian, enlazadas)" y hooks deterministas en `.claude/scripts/` clasifican/indexan, dejando el juicio (escribir/enlazar notas) al agente. Existe también la skill "Obsidian Memory System" con almacenamiento dual (corto plazo de sesión + largo plazo de conocimiento) y espacios de memoria aislados por proyecto auto-detectados desde Git.

### 4. Mejores MCPs para desarrollo (2025-2026)

**Los 5 esenciales** (consenso de múltiples fuentes): **Filesystem, GitHub, Context7 (docs en vivo), Playwright (automatización de navegador) y Sequential Thinking (razonamiento multi-paso).**

| MCP                                  | Para qué                                                   | Instalación                                                                                                     |
| ------------------------------------ | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **filesystem**                       | Operaciones de archivos fiables en codebases grandes       | `claude mcp add filesystem -- npx -y @modelcontextprotocol/server-filesystem /ruta`                             |
| **github**                           | Issues, PRs, CI/CD, búsqueda cross-repo                    | `claude mcp add --transport http github https://api.githubcopilot.com/mcp/` (OAuth)                             |
| **context7** (Upstash)               | Docs versionadas en vivo de React/Next/Flutter/etc.        | `claude mcp add context7 -- npx -y @upstash/context7-mcp@latest`                                                |
| **playwright** (Microsoft)           | Testing en navegador real; reemplaza Puppeteer (archivado) | `claude mcp add playwright -s user -- npx -y @playwright/mcp@latest`                                            |
| **sequential-thinking**              | Razonamiento estructurado/reflexivo                        | `claude mcp add sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking`                 |
| **memory** (knowledge-graph oficial) | Memoria persistente vía grafo (JSONL local)                | `claude mcp add memory -e MEMORY_FILE_PATH=./.claude/memory.json -- npx -y @modelcontextprotocol/server-memory` |
| **clangd-lsp** (oficial Anthropic)   | Inteligencia de símbolos C/C++                             | `/plugin install clangd-lsp@claude-plugins-official`                                                            |

**Por stack:**

- **React/Next.js:** Context7 (docs vivos), Playwright (verificación visual), Figma MCP oficial (`claude mcp add --transport http figma https://mcp.figma.com/mcp`), Next.js DevTools MCP (`next-devtools` con `get_errors`/`get_routes`/`get_logs` para detectar hydration mismatches).
- **C++:** clangd-LSP oficial + `felipeerias/clangd-mcp-server` (requiere `compile_commands.json` vía `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) + `DeusData/codebase-memory-mcp` (grafo estructural, soporta C/C++ vía tree-sitter + LSP híbrido).
- **Python:** Context7, memory-MCP, y subagent `python-expert`.
- **Flutter:** Context7 para docs de Flutter/Dart/Riverpod; subagent `flutter-expert`.

**Dónde encontrar MCPs:** smithery.ai, mcp.so, glama.ai, `awesome-mcp-servers`, `awesome-claude-code`, mcpservers.org y la documentación oficial de Anthropic.

**Configuración de múltiples MCPs y scopes** (3 niveles):

- **Local** (default): se guarda en `~/.claude.json` bajo la ruta del proyecto; privado.
- **Project**: archivo `.mcp.json` en la raíz del proyecto (commiteable, compartido con el equipo). ⚠️ Bug conocido: `.mcp.json` debe estar en la **raíz del proyecto**, no en `.claude/.mcp.json` (no se carga bien ahí).
- **User**: global a todos los proyectos.

Usa variables de entorno para secretos (`${GITHUB_TOKEN}`) para poder commitear `.mcp.json` sin filtrar credenciales. El nombre `workspace` está reservado. Una lista corta de tools importa: el modelo evalúa cada tool en cada turno, así que demasiados MCPs ralentizan y aumentan errores de selección. **MCP Tool Search** (lanzado el **14 de enero de 2026 en Claude Code 2.1.7**) habilita lazy-loading: según Thariq Shihipar (Anthropic), "Tool Search allows Claude Code to dynamically load tools into context when MCP tools would otherwise take up a lot of context." En los benchmarks de Anthropic, 50+ tools pasan de ~77K a ~8,7K tokens (≈85% menos overhead, preservando ~95% de la ventana de contexto); se activa automáticamente cuando las tools superan el ~10% del contexto.

### 5. CLAUDE.md y configuración

**Jerarquía de CLAUDE.md:**

- `~/.claude/CLAUDE.md` — global, todos los proyectos (preferencias personales).
- `./CLAUDE.md` — raíz del proyecto, commiteable (contexto de equipo).
- `./CLAUDE.local.md` — overrides personales (gitignored).
- Directorios padre/hijo: en monorepos se cargan automáticamente los padres; los hijos on-demand cuando Claude lee un archivo en ese subdirectorio.

**Mejores prácticas (consenso fuerte):**

- **Brevedad:** mantenerlo corto. HumanLayer mantiene su root CLAUDE.md bajo 60 líneas; consenso general <300 líneas, y algunos reportan que sobre 80 líneas Claude empieza a ignorar partes. Razón técnica: LLMs frontier-thinking siguen ~150-200 instrucciones con consistencia razonable.
- **Patrón WHY/WHAT/HOW:** qué hace el proyecto (1-2 líneas), comandos esenciales, mapa de directorios, convenciones no-default.
- **Progressive disclosure con `@imports`:** en vez de embeber `@docs/api-guide.md` (que mete todo el archivo en contexto cada sesión), indícale _cuándo_ leerlo ("Para temas de Stripe, ver docs/stripe-guide.md").
- **No uses CLAUDE.md como linter:** usa hooks/formatters. No incluyas instrucciones de personalidad ("eres un senior") — desperdician tokens.
- **Genera con `/init`** y refina. Cuando Claude se equivoca, dile que actualice CLAUDE.md (bucle de feedback vivo).

**settings.json — jerarquía y precedencia** (de mayor a menor): Managed (no overridable) → CLI args → Local → Project → User. En Windows `~/.claude` resuelve a `%USERPROFILE%\.claude`. Las reglas de permisos se _fusionan_ entre scopes (deny siempre gana). Opciones clave: `model`, `cleanupPeriodDays`, `permissions`, `hooks`, `disableAllHooks`.

**Hooks** (control determinista; en `.claude/settings.json` o `~/.claude/settings.json`):

- Eventos: SessionStart/SessionEnd (1/sesión), UserPromptSubmit/Stop (1/turno), PreToolUse/PostToolUse (cada tool call), SubagentStop, Notification, PreCompact.
- **PreToolUse**: inspecciona/bloquea antes de ejecutar (exit code 2 = bloquea; o JSON con `permissionDecision: "deny"`).
- **PostToolUse**: formateo/validación después (no puede deshacer).
- **Stop con exit 2**: fuerza a Claude a seguir trabajando (¡cuidado con loops infinitos — chequea `stop_hook_active`!).
- Usa `$CLAUDE_PROJECT_DIR` para rutas fiables. Los hooks aplican recursivamente a subagents.

Ejemplos de alto valor:

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
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"$CLAUDE_TOOL_INPUT\" | grep -qE 'rm -rf|DROP TABLE' && exit 2 || exit 0"
          }
        ]
      }
    ]
  }
}
```

### 6. Multi-dispositivo con OneDrive

**⚠️ Hallazgo crítico:** OneDrive NO soporta symlinks ni junctions de forma fiable. Microsoft confirma: "OneDrive no soporta nativamente la sincronización de enlaces simbólicos o junctions… sincronizará el archivo/carpeta real apuntado, no el symlink". Esto causa subidas masivas accidentales y sincronización colgada. **Por tanto, la estrategia clásica de dotfiles con symlinks dentro de la carpeta de OneDrive falla en Windows.**

**Estrategia recomendada (la que funciona):**

1. **Versiona `~/.claude` con git** (repo "claude-code-dotfiles") con un **allowlist explícito** de archivos a versionar (no todo el directorio). Sincroniza: `settings.json`, `CLAUDE.md`, `commands/`, `agents/`, `rules/`, `skills/`. **NO** sincronices: `.credentials.json`, `history.jsonl`, `projects/`, `file-history/`, `cache/`, `sessions/`, `telemetry/`, `plugins/cache/`.
2. Para automatizar, herramientas como **chezmoi** (gestor de dotfiles con plantillas) permiten configs por-máquina (`{{ if eq .chezmoi.hostname "mini-1" }}`) y auto-descarga de skills externos desde GitHub con `refreshPeriod`. Comandos: `chezmoi init`, `chezmoi apply`, `chezmoi update`.
3. **Re-autentica credenciales en cada máquina** (nunca sincronices `.credentials.json`; en macOS está en Keychain).
4. **El vault de Obsidian SÍ va en OneDrive** — son .md planos, sincronizan sin problemas y son tu memoria compartida real entre dispositivos. (Alternativa más robusta: Obsidian Git o Obsidian Sync para evitar conflictos de sync.)
5. ⚠️ **Paths absolutos de memoria por proyecto:** Claude Code codifica la ruta absoluta del proyecto (`projects/-Users-tu-code-proyecto/memory/`). Si el username/estructura difiere entre máquinas, los archivos de memoria por proyecto no coinciden y `--resume` no encuentra la sesión. Usa la misma estructura de rutas en todas las máquinas si quieres continuidad de sesiones.

**Si necesitas sincronizar carpetas fuera de la jerarquía de OneDrive** (workaround documentado): mueve la carpeta _real_ dentro de OneDrive y crea el junction _fuera_ apuntando a ella (el orden inverso del intuitivo). Aun así, OneDrive no detecta cambios dentro de junctions de forma fiable — preferir git/Syncthing.

**Multi-cuenta (personal/trabajo/cliente)** — solución oficial de Anthropic: la variable de entorno **`CLAUDE_CONFIG_DIR`**. Cada directorio es un Claude Code completamente aislado (credenciales, settings, history, plugins). Alias:

```bash
alias claude-personal='CLAUDE_CONFIG_DIR=~/.claude-personal command claude'
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work command claude'
```

Para compartir history entre cuentas: `ln -sf ~/.claude/projects ~/.claude-work/projects`. **⚠️ En Windows hay una complicación:** Claude Code también guarda estado en `~/.claude.json` (fuera de `.claude/`), que se convierte en punto de conflicto compartido. La solución probada (Josh Grossman) es dar a cada instancia un _home directory_ completamente separado vía `$env:USERPROFILE` falso en una función de PowerShell, más symlinks para no duplicar binarios. En proyectos que siempre usan una cuenta, un `.env` con direnv puede fijar el `CLAUDE_CONFIG_DIR` automáticamente.

### 7. Estructura de directorios recomendada en OneDrive

```
OneDrive/
└── DevSetup/
    ├── claude-dotfiles/          # repo git (versionado, NO symlinked desde OneDrive)
    │   ├── CLAUDE.md             # global
    │   ├── settings.json
    │   ├── commands/
    │   ├── agents/
    │   ├── skills/
    │   ├── rules/
    │   ├── claude-md-templates/  # plantillas por stack
    │   │   ├── react-nextjs.md
    │   │   ├── python-fastapi.md
    │   │   ├── flutter.md
    │   │   └── cpp-cmake.md
    │   ├── mcp/                  # .mcp.json de ejemplo + servers custom
    │   └── bootstrap/
    │       ├── setup.ps1         # Windows
    │       └── setup.sh          # macOS
    ├── ObsidianVault/            # memoria compartida (SÍ via OneDrive o Obsidian Git)
    │   ├── 00-Inbox/
    │   ├── 10-Projects/          # 1 nota/proyecto + ADRs
    │   ├── 20-Areas/
    │   ├── 30-Resources/
    │   ├── 40-Archive/
    │   ├── brain/                # conocimiento durable (topic notes)
    │   ├── daily/                # daily notes
    │   └── templates/            # Templater
    └── projects/                 # código (mejor en disco local, NO en OneDrive)
```

**Importante:** el código fuente (con `node_modules`, builds C++, etc.) NO debe vivir en OneDrive — el rendimiento de I/O y los miles de archivos pequeños lo hacen inviable. Mantén el código en disco local; sincroniza solo config (git) y conocimiento (vault).

**Script de bootstrap (Windows, conceptual):** clona el repo de dotfiles desde git, copia (no symlink) los archivos a `%USERPROFILE%\.claude\`, instala los MCPs con `claude mcp add`, registra el marketplace de Superpowers e instala el plugin.

### 8. Mejores prácticas por stack (con fuentes)

**React/Next.js:**

- En CLAUDE.md declara explícitamente App Router + Server Components por defecto: "Usa Server Components por defecto, añade 'use client' solo cuando sea necesario", "Sin tipos `any`", "Route handlers en app/api/[route]/route.ts". Incluye sección "Off-Limits".
- Gotcha Next.js 16: la lógica de middleware vive en `proxy.ts`, no `middleware.ts` — una línea en CLAUDE.md lo previene.
- MCPs: Context7 (versiona docs — evita que genere APIs deprecadas), Playwright (siempre `browser_snapshot` antes de interactuar), Figma oficial, Next.js DevTools MCP.
- Hook estrella: prettier + eslint en PostToolUse. "CLAUDE.md dice qué hacer; los hooks lo garantizan."
- Starter kits: supastarter, `yashiel/claude-code-starter` (Next 15 + React 19 + shadcn), `darraghh1/my-claude-setup`.

**C++:**

- Genera CLAUDE.md con `/init` (captura targets CMake). Incluye checklist: C++ Core Guidelines, clang-tidy passing, `-Wall -Wextra` sin warnings, ASan/UBSan limpios, cobertura gcov/llvm-cov, cppcheck, Valgrind. Conan para paquetes.
- **clangd es la clave:** plugin oficial `clangd-lsp` o `felipeerias/clangd-mcp-server`. Requiere `compile_commands.json`. Sin LSP, Claude hace pattern-matching de texto y "puede caer en el símbolo equivocado" (headers/templates/cross-module poco fiables).
- Pain point: en codebases C++ grandes se llega al límite de ventana de contexto rápido; el scoping per-subdirectorio en monorepos compilados es más difícil.
- `DeusData/codebase-memory-mcp` indexa a grafo (⚠️ sus métricas "99% menos tokens" son del propio proyecto/preprint, no benchmarks independientes; y un issue reporta que requiere un hint en CLAUDE.md para que Claude lo use, contradiciendo el README).

**Flutter:**

- Subagents especializados (UI/Logic/Backend/Test con Riverpod, Flutter Hooks, Firebase). Claude Code 2.0 permite paralelizar: "UI Agent construye pantallas, Logic Agent conecta providers, Backend Agent configura Firebase, Test Agent genera golden tests."
- Template CLAUDE.md de Flutter con Riverpod en `MuhammadUsmanGM/claude-code-best-practices`.

**Python:**

- Subagent `python-expert`; usa `uv` para entornos; memory-MCP para preferencias persistentes (const sobre let, etc., aplicado a estilo).

**Subagents y orquestación (general):**

- Frontmatter de subagent: `name`, `description` (usa "PROACTIVELY" para auto-invocación), `tools` (allowlist; omitir = hereda todos), `model` (sonnet/opus/haiku/inherit), `skills` (preload), `hooks`, `memory` (scope project/user/local).
- Explore y Plan son los únicos built-in que omiten CLAUDE.md y git status (para investigación rápida/barata).
- Subagents con scope `memory: project` comparten conocimiento vía control de versiones (el system prompt incluye las primeras 200 líneas / 25KB de MEMORY.md).
- Patrón de pipeline (PubNub): PM → Architect → Implementer → Test, con hooks que invocan un LLM externo para QA entre etapas.
- Anthropic recomienda subagents para (a) paralelización y (b) gestión de contexto (devuelven solo lo relevante).

## Recommendations — Plan de acción por fases

**Fase 0 — Fundación (1 laptop, ~1h).**

1. Instala Claude Code y Obsidian. Crea el vault en `OneDrive/DevSetup/ObsidianVault` con estructura PARA + `brain/` + `daily/` + `templates/`.
2. Instala plugins Obsidian: Obsidian Git (auto-commit cada 10-15 min — esto es tu red de seguridad contra corrupción), Templater, Dataview/Bases, Tasks, QuickAdd, Periodic Notes, Smart Connections.
3. Crea repo git `claude-dotfiles` (privado) con allowlist. Inicializa `~/.claude/CLAUDE.md` global (<60 líneas).

**Fase 1 — Agentes y MCPs.** 4. `/plugin marketplace add obra/superpowers-marketplace` + `/plugin install superpowers@superpowers-marketplace`. 5. Instala los MCPs esenciales (filesystem, github, context7, playwright, sequential-thinking, memory) a scope **user**. Conecta Obsidian con `iansinnott/obsidian-claude-code-mcp` (o filesystem-MCP apuntando al vault). 6. Añade hooks de formato (PostToolUse prettier/eslint) y seguridad (PreToolUse bloqueando `rm -rf`).

**Fase 2 — Plantillas por stack.** 7. Crea `claude-md-templates/` con un CLAUDE.md por stack (React/Next, Python, Flutter, C++) y cópialos a cada proyecto al iniciarlo (no symlink). Para C++ instala clangd y genera `compile_commands.json`. 8. Instala subagents por lenguaje desde VoltAgent/awesome-claude-code-subagents según necesites.

**Fase 3 — Multi-dispositivo.** 9. En laptops 2 y 3: clona el repo de dotfiles, corre el script bootstrap que **copia** la config a `~/.claude`, re-autentica, instala MCPs. Sincroniza el vault vía OneDrive (o mejor, Obsidian Git para evitar conflictos). 10. Usa **misma estructura de rutas de proyecto** en todas las máquinas para continuidad de sesiones.

**Fase 4 — Multi-cuenta.** 11. Configura `CLAUDE_CONFIG_DIR` con alias por cuenta (`claude-personal`, `claude-work`). En Windows, usa la técnica de home-directory separado de Josh Grossman si necesitas correr 2 cuentas simultáneas.

**Benchmarks/umbrales que cambian las recomendaciones:**

- Si tu CLAUDE.md supera ~80-150 líneas → mueve detalle a skills/rules con progressive disclosure.
- Si tienes >15-20 MCPs activos → MCP Tool Search se activa automáticamente cuando las tools superan ~10% del contexto; aun así, desactiva los que no uses (degradación de selección de tools).
- Si el vault supera ~2.000 notas → deja que Smart Connections indexe overnight; considera QMD para búsqueda semántica.
- Si OneDrive empieza a colgar la sync → busca reparse points (`Get-ChildItem -Recurse | Where Attributes -match 'ReparsePoint'`) y elimínalos; migra a git/Syncthing.

## Caveats

- **Corrupción de vault:** el riesgo más serio. Sin git con commits frecuentes, Claude puede sobrescribir o "obsoletar" notas. Obligatorio Obsidian Git.
- **OneDrive + symlinks:** no fiable en Windows. No bases tu sync de config en symlinks dentro de OneDrive; usa git para config y OneDrive solo para .md del vault.
- **Credenciales:** nunca sincronices `.credentials.json` ni las commitees. Re-autentica por máquina.
- **Métricas de vendors:** las cifras de `codebase-memory-mcp` (99% menos tokens, 83% calidad) son auto-reportadas; trátalas como claims, no benchmarks independientes.
- **Variables de entorno de hooks:** los nombres varían entre fuentes (`$CLAUDE_TOOL_INPUT_FILE_PATH` vs `.tool_input.file_path` vía jq); verifica contra la doc oficial actual de hooks.
- **Política corporativa:** correr tu cuenta personal de Claude en una laptop de trabajo puede violar políticas de IT; consúltalo antes.
- **`.mcp.json` en `.claude/`:** bug conocido — debe ir en la raíz del proyecto, no en `.claude/.mcp.json`.
- **Versiones:** detalles como "LSP v2.0.74, 11 lenguajes" provienen de fuentes secundarias; verifica contra release notes oficiales. Fecha de esta investigación: junio 2026.
