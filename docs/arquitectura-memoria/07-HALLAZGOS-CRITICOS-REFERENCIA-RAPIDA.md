# Hallazgos Críticos — Hoja de Referencia Rápida
## Los datos que cambian decisiones de arquitectura

> Este documento extrae los hallazgos más contraintuitivos y accionables de toda la investigación.
> Diseñado para consulta rápida antes de tomar decisiones de setup o configuración.

---

## 🔴 Hallazgos que rompen suposiciones comunes

### H1: Los grafos de memoria no siempre superan al markdown

**Dato**: Letta demostró (agosto 2025) que archivos planos logran **74% en LOCOMO**, superando al **68.5% del grafo de Mem0**.

**Dato**: Mem0 eliminó su capa de grafo en la versión OSS (PR #4805, abril 2026) porque el grafo era 3× más lento y costaba 2× más tokens, con ganancia de solo 1.5 puntos en el benchmark global.

**Implicación**: No añadir Graphiti solo porque "los grafos son más avanzados". Añadirlo solo si se necesita razonamiento temporal sobre hechos cambiantes.

---

### H2: FalkorDB + OneDrive directo es incompatible (riesgo de corrupción)

**Dato**: FalkorDB mantiene locks activos sobre `dump.rdb` y `appendonly.aof`. OneDrive puede interrumpir escrituras mid-snapshot.

**Implicación**: Nunca configurar `FALKORDB_DATA_PATH` apuntando a OneDrive sin el protocolo "apaga el container antes de cambiar de laptop". La Estrategia A (datos locales + backups periódicos) es la opción segura.

---

### H3: Los MCPs silenciosamente consumen decenas de miles de tokens

**Dato**: Cada MCP conectado carga 10,000–20,000 tokens de esquema en cada sesión.

**Dato**: 5 MCPs conectados = hasta **70,000 tokens de overhead** antes de escribir una línea.

**Dato**: `ENABLE_TOOL_SEARCH` reduce esto en **85%** (de ~70,000 a ~8,700 tokens).

**Implicación**: Activar `ENABLE_TOOL_SEARCH` siempre. Desconectar MCPs no usados en la sesión actual.

---

### H4: Un CLAUDE.md de 3,847 tokens es 12× peor que uno de 312 tokens

**Dato**: El token-optimizer benchmark comparó CLAUDE.md auto-generado (3,847 tokens) vs manual optimizado (312 tokens) → **91.9% menos overhead** con calidad equivalente.

**Dato**: Claude empieza a ignorar instrucciones después de ~150 instrucciones. Sobre ~80 líneas, la compliance se degrada.

**Implicación**: CLAUDE.md < 500 tokens. Todo lo demás va en Skills con progressive disclosure o en rules con path scoping.

---

### H5: Graphify en modo AST consume exactamente 0 tokens propios

**Dato**: El primer pass de Graphify usa Tree-sitter (análisis estático puro) — sin llamadas a LLM, sin API keys, sin costo.

**Dato**: El segundo pass (PDFs, imágenes, markdown semántico) sí usa LLM — es opcional.

**Implicación**: Instalar Graphify para cualquier proyecto con más de 50 archivos. El costo-beneficio es positivo por definición (costo = 0, beneficio = contexto estructural).

---

### H6: add_episode en Graphiti es asíncrono (~25 segundos)

**Dato**: Cuando Claude llama a `add_episode`, el episodio se encola y procesa en background. Los hechos **no aparecen en `search_facts` inmediatamente**.

**Implicación**: No esperar confirmación de `add_episode` antes de continuar trabajando. Esperar 30+ segundos antes de buscar un episodio recién guardado.

---

### H7: Anthropic tiene soporte experimental para structured output en Graphiti

**Dato**: Graphiti usa JSON schema para extracción de entidades. OpenAI y Gemini tienen modo nativo; Anthropic es experimental.

**Dato**: Con Claude Haiku en extracción, hay tasa mayor de fallos silenciosos de JSON schema — el episodio se guarda pero las entidades no se extraen.

**Implicación**: Usar OpenAI (gpt-4.1-mini) o Gemini para el LLM de extracción de Graphiti. Claude Code sigue siendo el agente principal — son capas separadas.

---

### H8: OneDrive no soporta symlinks en Windows

**Dato**: Microsoft documenta explícitamente: "OneDrive no soporta nativamente la sincronización de symlinks o junctions en Windows".

**Implicación**: La estrategia clásica de dotfiles con symlinks NO funciona si el repo está dentro de la carpeta de OneDrive en Windows. Usar copias + git para detectar y propagar cambios.

---

### H9: Desconectar un MCP mid-sesión borra la caché de Claude Code

**Dato**: En Claude Code, conectar o desconectar un MCP en medio de una sesión invalida el prompt cache completo.

**Implicación**: Configurar los MCPs necesarios al inicio de la sesión, no durante. El overhead de decidir qué MCPs conectar al inicio se amortiza en toda la sesión.

---

### H10: Los benchmarks de vendors son incomparables entre sí

**Dato**: Zep reportó 84% en LOCOMO → corregido a 75.14%. El equipo de Mem0 lo reprodujo en 58.44%.

**Dato**: Cada vendor ejecuta los benchmarks del competidor con su configuración más favorable.

**Implicación**: Tratar cualquier número de benchmark de un solo vendor como marketing. Buscar benchmarks reproducidos por terceros o papers peer-reviewed. El benchmark más honesto del análisis: Mem0 publicó datos donde el contexto completo (72.9%) supera a su propio sistema (66.9%).

---

## 🟡 Datos útiles de referencia rápida

### Tokens de overhead por componente

| Componente | Tokens al inicio de sesión |
|------------|---------------------------|
| Sistema + CLAUDE.md base | ~20,000–30,000 |
| Cada MCP conectado | +10,000–20,000 |
| Con ENABLE_TOOL_SEARCH | ~8,700 total (todos los MCPs) |
| CLAUDE.md de 3,847 tokens | +3,847 por cada mensaje |
| CLAUDE.md de 312 tokens | +312 por cada mensaje |
| Rules con path scoping | 0 si el path no coincide |

### Latencias de retrieval

| Sistema | Latencia P50 | Latencia P95 |
|---------|-------------|-------------|
| Markdown plano (filesystem) | <5ms | <10ms |
| Obsidian MCP | <20ms | <50ms |
| Graphify (AST) | <50ms | <200ms |
| Graphiti + FalkorDB (lectura) | <150ms | <300ms |
| Contexto completo (dump) | 17,000ms (TTFT) | — |

### Costos de escritura con OpenAI gpt-4.1-mini

| Operación | Costo aproximado |
|-----------|-----------------|
| add_episode en Graphiti (500 palabras) | ~$0.001–0.003 |
| 10 episodios/sesión | ~$0.01–0.03 |
| Uso mensual intensivo (500 episodios) | ~$0.50–1.50 |
| Graphify Pass 1 (AST) | $0.00 |
| Graphify Pass 2 (semántico, por archivo grande) | ~$0.01–0.05 |

### Capacidad de FalkorDB local

| Métrica | Valor |
|---------|-------|
| Grafos simultáneos | Ilimitado (un grafo por group_id) |
| Nodos por grafo (práctico) | Decenas de miles sin problema |
| Memoria RAM (FalkorDB vacío) | ~50–100MB |
| Memoria RAM (grafo 1,000 nodos) | ~200–500MB |
| Consultas P99 | <10ms (FalkorDB benchmark) |

---

## 🟢 Decisiones validadas

✅ **Obsidian en OneDrive**: los archivos .md sincronizan perfectamente — sin locks, sin conflictos.

✅ **Git para dotfiles, no symlinks en OneDrive**: copia + git es más confiable que symlinks en Windows.

✅ **Superpowers plugin**: zero-dependency, mantenido, 200k+ instalaciones.

✅ **Context7 para docs de librerías**: sin Context7, Claude genera APIs de versiones anteriores a agosto 2025.

✅ **Obsidian Git con auto-commit**: red de seguridad obligatoria contra corrupción por Claude.

✅ **CLAUDE_CONFIG_DIR para multi-cuenta**: la solución oficial de Anthropic, funciona en todas las plataformas.

✅ **Backups de FalkorDB cada 4 horas**: el peor caso de pérdida de datos en Estrategia A es 4 horas.

---

*Última actualización: Julio 2026 | Investigación basada en fuentes primarias: GitHub repos, docs oficiales, papers, benchmarks reproducibles*
