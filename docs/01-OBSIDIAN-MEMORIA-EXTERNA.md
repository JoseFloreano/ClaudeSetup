# Obsidian como Memoria Externa para Claude Code
## Justificación, Hallazgos y Configuración

---

## 1. Por qué Obsidian (y no otra herramienta)

### El problema de fondo

Claude Code no tiene memoria entre sesiones. El GitHub Issue #14227 lo confirma explícitamente:

> *"Claude Code starts every session with zero context. There is no memory of previous sessions, previous work, or accumulated understanding of the user's projects and preferences."*

Necesitamos un sistema externo que actúe como "cerebro auxiliar" del agente. Los candidatos evaluados fueron:

| Sistema | Ventajas | Desventajas |
|---------|----------|-------------|
| **Obsidian** | Archivos .md planos, versionable con git, inspeccionable, sin vendor lock-in, offline-first | Requiere configuración inicial |
| Notion | UI pulida, colaborativo | Propietario, requiere internet, sin acceso directo de archivo |
| Roam Research | Excelente para bidireccional | Propietario, caro, sin archivos locales |
| Logseq | Open source, similar a Obsidian | Menor ecosistema de plugins |
| Base de datos vectorial | Búsqueda semántica nativa | Opaca, no inspeccionable, requiere infra |

**Obsidian gana** porque sus archivos `.md` son ciudadanos de primera clase del sistema de archivos: los puede leer Claude Code directamente, se pueden versionar con git, se pueden sincronizar con OneDrive/Obsidian Git, y el desarrollador puede inspeccionarlos y editarlos con cualquier editor.

### El argumento de Letta (agosto 2025)

El equipo de Letta (antes MemGPT) publicó *"Is a Filesystem All You Need?"* y demostró que poner transcripciones de conversaciones directamente en archivos planos y darle al agente acceso de búsqueda logra **74.0%** en el benchmark LOCOMO, por encima del **68.5%** del grafo de Mem0. El argumento: los LLMs de frontera están optimizados para búsqueda iterativa en archivos, no para sistemas de memoria especializados.

Esto no invalida los grafos (tienen ventajas reales para relaciones complejas), pero confirma que markdown bien organizado es un punto de partida sólido y competitivo.

---

## 2. Arquitectura del vault para desarrollo con IA

### Estructura recomendada (PARA + extensiones para dev)

```
ObsidianVault/
├── 00-Inbox/                    ← notas sin clasificar, captura rápida
├── 10-Projects/                 ← 1 carpeta por proyecto activo
│   ├── react-dashboard/
│   │   ├── _PROJECT.md          ← resumen del proyecto (cargado en CLAUDE.md vía @import)
│   │   ├── ADRs/                ← Architecture Decision Records
│   │   │   ├── ADR-001-state-management.md
│   │   │   └── ADR-002-auth-strategy.md
│   │   ├── bugs/                ← bugs documentados con causa raíz
│   │   └── sessions/            ← importaciones de sesiones de Claude
│   ├── flutter-app/
│   └── python-api/
├── 20-Areas/                    ← áreas de responsabilidad continua
│   ├── dev-conventions/         ← convenciones globales del dev
│   └── tech-radar/              ← tecnologías evaluadas
├── 30-Resources/                ← conocimiento de referencia
│   ├── react/
│   ├── flutter/
│   └── python/
├── 40-Archive/                  ← proyectos terminados
├── brain/                       ← conocimiento durable (topic notes)
│   ├── state-management.md
│   ├── authentication-patterns.md
│   └── flutter-riverpod.md
├── daily/                       ← daily notes (Periodic Notes plugin)
└── templates/                   ← plantillas Templater
    ├── project-note.md
    ├── adr.md
    ├── bug-report.md
    └── session-import.md
```

### Principios del sistema Zettelkasten para código

Basado en el análisis de `lucasrosati/claude-code-memory-setup` (caso documentado con 71.5× reducción de tokens):

1. **Atomicidad**: 1 concepto por nota permanente
2. **Densidad de enlaces**: mínimo 2 wikilinks `[[nota]]` por nota permanente
3. **Frontmatter obligatorio** en toda nota:
   ```yaml
   ---
   title: Riverpod State Management Pattern
   tags: [flutter, state, riverpod]
   created: 2026-07-12
   updated: 2026-07-12
   status: active
   type: permanent
   project: flutter-app
   ---
   ```
4. **Kebab-case en nombres de archivo**: `auth-flow.md`, no `Auth Flow.md`
5. **Solo wikilinks internos**: `[[auth-flow]]`, nunca `[texto](./auth-flow.md)`

---

## 3. Plugins esenciales y su justificación

### Stack mínimo viable (< 20 plugins — sin impacto perceptible de rendimiento)

| Plugin | Función | Por qué es esencial |
|--------|----------|---------------------|
| **Obsidian Git** | Auto-commit y sync | Red de seguridad contra corrupción por Claude. Auto-commit cada 10-15 min |
| **Templater** | Plantillas con JS | Frontmatter automático, fechas, variables de proyecto |
| **Dataview / Bases** | Consultas SQL-like | Indexar notas por proyecto, estado, fecha |
| **Periodic Notes** | Daily/weekly notes | Contexto temporal, journal de sesiones |
| **QuickAdd** | Captura rápida | Añadir notas sin abrir Obsidian completo |
| **Smart Connections** | Búsqueda semántica IA | Búsqueda por significado, no solo texto exacto |

> ⚠️ **Umbral crítico**: más de 40 plugins genera lentitud y conflictos documentados. El stack de 6 plugins listados cubre el 95% de los casos de uso para desarrollo.

---

## 4. Conectar Obsidian con Claude Code

### Método A: Plugin MCP (recomendado)

`iansinnott/obsidian-claude-code-mcp` instala un servidor MCP directamente en Obsidian. Claude Code se conecta automáticamente por WebSocket en el **puerto 22360**.

```json
// En claude_desktop_config.json (para Claude Desktop)
// Claude Code se conecta directamente — no necesita esta config
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

**Capacidades que habilita:**
- Claude puede leer y escribir notas directamente en el vault
- Búsqueda por texto en todo el vault
- Crear y actualizar notas durante la sesión

### Método B: MCP REST (alternativa estable)

`MarkusPfundstein/mcp-obsidian` (2,800+ stars, 344 forks) usa la REST API del plugin community "Local REST API". Expone 7 herramientas:

```
list_files_in_vault    → inventario del vault
list_files_in_dir      → directorio específico
get_file_contents      → contenido de una nota
search                 → búsqueda full-text
patch_content          → editar sección específica
append_content         → añadir al final de una nota
delete_file            → eliminar nota
```

Instalación:
```bash
claude mcp add obsidian -s user -- uvx mcp-obsidian
```

### Método C: Filesystem MCP (más simple, más seguro)

El vault es solo una carpeta de archivos `.md`. Apuntar el filesystem-MCP al vault da acceso completo sin plugins adicionales:

```bash
claude mcp add obsidian-vault -s user -- \
  npx -y @modelcontextprotocol/server-filesystem \
  ~/OneDrive/DevSetup/ObsidianVault
```

**Cuándo usar cada método:**

| Escenario | Método recomendado |
|-----------|--------------------|
| Quiero que Claude escriba notas automáticamente | A (Plugin MCP) |
| Necesito búsqueda semántica desde Claude | A o B |
| Solo lectura, máxima seguridad | C (Filesystem MCP) |
| Vault en OneDrive con sync activo | C (sin riesgo de locks) |

---

## 5. El riesgo crítico: corrupción del vault

### El problema documentado

Cuando Claude tiene acceso de escritura al vault, puede:
- Sobrescribir notas existentes si no verifica primero
- Crear duplicados del mismo conocimiento (10 sesiones → 10 notas casi idénticas)
- Modificar la estructura de carpetas sin avisar

### La solución: Obsidian Git como red de seguridad

**Configuración obligatoria:**

```
Auto-commit interval: 10 minutos
Auto-pull on startup: Habilitado
Commit message: "auto: {{date}} {{hostname}}"
Files to commit: All changes
```

Con auto-commit cada 10 minutos, el peor caso de pérdida de datos es 10 minutos de trabajo. Cualquier modificación de Claude es reversible con `git revert`.

### Protocolo search-before-save

En la instrucción de CLAUDE.md de memoria:

```markdown
## Memory Rules
- SIEMPRE busca en el vault antes de crear una nota nueva
- Si existe una nota similar (>80% de similitud), actualiza en vez de crear
- Nunca elimines notas sin confirmar con el usuario
- Nunca modifiques la estructura de carpetas sin preguntar
```

---

## 6. Obsidian + OneDrive: configuración correcta

### Lo que funciona

Los archivos `.md` del vault son texto plano. OneDrive los sincroniza perfectamente:
- Sin locks de archivo durante la sync
- Sin conflictos de formato
- Historial de versiones de OneDrive como backup adicional
- Accesibles desde cualquier laptop inmediatamente al sincronizar

### Lo que no funciona

- **Symlinks**: OneDrive en Windows no sincroniza symlinks confiablemente
- **La carpeta `.obsidian/` de settings**: contiene archivos de caché y configuración que pueden conflictuar entre dispositivos. Gitignorear lo volátil:
  ```gitignore
  .obsidian/workspace.json
  .obsidian/cache
  .obsidian/.pdf/
  ```
- **El grafo de smart connections**: re-indexar es rápido, no vale la pena sincronizar

### Estructura en OneDrive

```
OneDrive/
└── DevSetup/
    └── ObsidianVault/        ← todo el vault aquí
        ├── .obsidian/        ← config (sincroniza con cuidado)
        ├── .gitignore        ← excluye caché y workspace
        ├── 00-Inbox/
        ├── 10-Projects/
        ...
```

---

## 7. Flujo de trabajo: cómo Claude usa el vault

### Al inicio de cada sesión

```markdown
# CLAUDE.md — sección Memory
Al inicio de cada sesión:
1. Busca en el vault: search("proyecto: [[nombre-proyecto]] decisiones recientes")
2. Lee el archivo 10-Projects/[proyecto]/_PROJECT.md
3. Consulta los últimos 3 ADRs del proyecto
4. Verifica si hay bugs documentados relacionados con la tarea actual
```

### Durante la sesión

```markdown
Cuando tomes una decisión de arquitectura importante:
1. Crea o actualiza el ADR correspondiente en 10-Projects/[proyecto]/ADRs/
2. Usa el template templates/adr.md
3. Linkea desde _PROJECT.md con [[ADR-XXX-tema]]

Cuando encuentres y resuelvas un bug no-obvio:
1. Documenta en 10-Projects/[proyecto]/bugs/[nombre-bug].md
2. Incluye: síntoma, causa raíz, fix, archivos modificados
```

### Al cerrar la sesión

```markdown
Antes de terminar:
1. Actualiza _PROJECT.md con el estado actual
2. Añade un bullet en daily/[fecha].md con lo trabajado
3. Si hubo decisiones importantes, crea/actualiza ADRs
```

---

## 8. Métricas documentadas de reducción de tokens

| Setup | Tokens por sesión | Reducción vs baseline |
|-------|------------------|----------------------|
| Sin memoria (grep everything) | ~150,000 | baseline |
| CLAUDE.md de 3,847 tokens | ~50,000 | 67% |
| CLAUDE.md de 312 tokens + rules scoped | ~30,000 | 80% |
| + Obsidian MCP (retrieval selectivo) | ~8,000–15,000 | 90–95% |
| + Graphify (grafo de codebase) | ~2,000–5,000 | 97% |

Fuente: caso documentado `lucasrosati/claude-code-memory-setup`, junio 2026. El caso más extremo documentado: 383 archivos dispersos + 100 transcripciones organizados en wiki → reducción del 95% de tokens en consultas.

> **Nota metodológica**: estas métricas provienen de casos individuales documentados en GitHub, no de benchmarks controlados independientes. Los resultados varían según el tamaño del codebase, la complejidad del proyecto y el patrón de uso.

---

*Siguiente: [Grafos vs Markdown — Análisis Comparativo](./02-GRAFOS-VS-MARKDOWN.md)*
