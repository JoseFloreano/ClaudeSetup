# Grafos vs Markdown: Análisis Comparativo
## Cuándo usar cada sistema, benchmarks honestos y hallazgos críticos

---

## 1. El mapa del territorio

La pregunta "¿grafos o markdown?" es falsa. Existen **cuatro tipos distintos de memoria** para agentes IA, y cada uno tiene una herramienta óptima diferente:

```
TIPO 1: Estructura del codebase
"¿Qué función llama a AuthService? ¿Qué archivos dependen de este módulo?"
→ GRAFO ESTÁTICO (Tree-sitter AST) — Graphify, code-review-graph

TIPO 2: Conocimiento del proyecto (decisiones, convenciones)
"¿Por qué usamos Riverpod? ¿Cuál es la estructura de carpetas acordada?"
→ MARKDOWN ESTRUCTURADO — Obsidian vault + MCP

TIPO 3: Memoria temporal de agente (hechos que cambian con el tiempo)
"¿Qué era verdad sobre este usuario/proyecto el martes pasado?"
→ GRAFO TEMPORAL — Graphiti + FalkorDB

TIPO 4: Personalización de usuario final
"Este usuario prefiere respuestas cortas y usa Python 3.12"
→ VECTOR STORE — Mem0 (para apps de usuario final, no para dev personal)
```

Confundir estos tipos lleva a over-engineering. Un desarrollador personal trabajando en sus propios proyectos no necesita Graphiti para todo — necesita el tipo correcto para cada cosa.

---

## 2. Benchmarks: los datos reales (con caveats)

### 2.1 Benchmark de precisión de memoria (conversaciones multi-sesión)

| Sistema | LongMemEval | LOCOMO | Notas |
|---------|-------------|--------|-------|
| Contexto completo (dump) | — | 72.9% | 26,000 tokens, 17s latencia |
| **Zep/Graphiti** | **63.8%** | ~75% | Grafo temporal, 300ms P95 |
| Mem0 v3 (vector) | 49.0% | 66.9% | Grafo eliminado en OSS |
| Mem0 con grafo | 49.0%+ | 68.5% | 3× más lento, 2× más tokens |
| Letta (archivos planos) | — | **74.0%** | Sin grafo especializado |
| Markdown simple | — | variable | Depende de organización |

**Hallazgo crítico #1**: El contexto completo (dump de todo en el prompt) sigue siendo el más preciso en LOCOMO, con 72.9%. Los sistemas de memoria especializados pierden algo de precisión pero ganan enormemente en latencia y costo. Esta tabla la publicó el propio equipo de Mem0 — un vendor raramente publica resultados que hacen a su producto parecer inferior.

**Hallazgo crítico #2**: Letta con archivos planos (74.0%) supera al grafo de Mem0 (68.5%). Los LLMs modernos están optimizados para búsqueda iterativa en archivos, no para sistemas de memoria especializados.

> ⚠️ **Advertencia de benchmarks**: Zep reportó inicialmente 84% en LOCOMO, luego corregido a 75.14%. El equipo de Mem0 lo reprodujo a 58.44%. Cada vendor ejecuta los benchmarks con su propia configuración optimizada. Tratar cualquier número único como marketing, no como fact.

### 2.2 Benchmark de reducción de tokens en codebase (Graphify)

| Escenario | Reducción documentada | Fuente |
|-----------|-----------------------|--------|
| Obsidian + Graphify (383 archivos + 100 transcripciones) | **71.5×** | lucasrosati/claude-code-memory-setup |
| code-review-graph (monorepo Next.js 27,700 archivos) | **49×** | benchmark propio del proyecto |
| 383 archivos → wiki organizado | **95%** | caso MindStudio (citando Karpathy) |
| CLAUDE.md de 3,847 → 312 tokens | **91.9%** | token-optimizer benchmark |
| Rules con path-scoping | **41%** overhead | caso documentado Zenn 2025 |

**Hallazgo crítico #3**: code-review-graph es honesto sobre sus limitaciones — para cambios de un solo archivo pequeño, el metadata estructural del grafo puede *superar* el tamaño del archivo original (reducción sub-1×). Los grafos de codebase solo ayudan a partir de cierta escala.

### 2.3 Costo de operación de cada sistema

| Sistema | Costo escritura | Costo lectura | Latencia lectura |
|---------|----------------|---------------|-----------------|
| Markdown plano | 0 tokens LLM | 0 tokens LLM | <10ms (filesystem) |
| Obsidian MCP | 0 tokens LLM | 0 tokens LLM | <50ms |
| Graphify (AST mode) | **0 tokens LLM** | 0 tokens LLM | <100ms |
| Graphify (semantic) | ~500–2,000 tokens | 0 tokens LLM | <200ms |
| memory-graph (SQLite) | 0 tokens LLM | 0 tokens LLM | <5ms |
| Graphiti + FalkorDB | **500ms–2s/episodio** (LLM call) | **0 tokens LLM** | 300ms P95 |
| Mem0 (vector) | ~200ms (extracción) | <100ms | 100–300ms |

**Hallazgo crítico #4**: Graphiti cobra el costo al **escribir**, no al leer. Cada `add_episode` invoca el LLM internamente para extraer entidades y relaciones (~1-3 llamadas). En lectura/búsqueda no llama al LLM — retrieval puro de grafo. Esto cambia el análisis de costos: si lees mucho y escribes poco, Graphiti es eficiente. Si cada turno de conversación genera un episodio, el costo puede ser elevado.

---

## 3. Por qué Mem0 eliminó su capa de grafo (abril 2026)

Este es el dato más contraintuitivo de la investigación y merece análisis detallado.

Mem0 construyó una capa de grafo opcional sobre Neo4j entre 2024 y 2025, disponible en PR #1718. En abril 2026, el commit `a488e190` (PR #4805) lo eliminó de la versión OSS. Las razones documentadas en sus propios benchmarks:

```
Métrica              Mem0 (vector)   Mem0g (grafo)   Diferencia
─────────────────────────────────────────────────────────────
LOCOMO overall       66.88           68.44           +1.56 puntos
Single-hop recall    mejor           peor            grafo pierde
Multi-hop recall     mejor           peor            grafo pierde
Temporal queries     peor            mejor           único caso donde grafo gana
Search latency       baseline        3× más lento
Token cost (write)   baseline        2× más tokens
```

**Conclusión de Mem0**: para el caso de uso principal (recordar preferencias y hechos recientes de usuarios), el grafo agrega complejidad sin beneficio neto suficiente. El grafo solo gana en consultas temporales — y lo hace pagando 2× en tokens y 3× en latencia.

Mem0 Cloud sigue ofreciendo grafo como feature de pago, lo que sugiere que tiene valor en algunos casos; simplemente no justifica la complejidad en la versión OSS de propósito general.

**Implicación práctica**: si el caso de uso no requiere explícitamente razonamiento temporal ("¿qué era verdad el martes pasado?") o traversal de relaciones complejas, markdown + vector search es más eficiente.

---

## 4. Cuándo los grafos SÍ ganan

Los grafos tienen ventajas reales y documentadas en escenarios específicos:

### 4.1 Relaciones explícitas que el texto no puede expresar

```
timeout_fix --CAUSES--> memory_leak --SOLVED_BY--> connection_pooling
                                    |
                                    +--SUPERSEDED_BY--> new_approach
```

Un markdown plano puede describir esta relación, pero no puede *travers arla*. Si necesitas "dame todos los bugs causados por memory leaks y sus soluciones", el grafo lo resuelve con una consulta; el markdown requiere que Claude lea todos los archivos y infiera la relación.

### 4.2 Razonamiento temporal sobre hechos cambiantes

Graphiti introduce el concepto de **validez bítemporal**:
- `valid_at / invalid_at`: cuándo fue verdad el hecho en el mundo real
- `created_at / expired_at`: cuándo el sistema supo del hecho

Esto permite consultas como: *"¿Qué librería usábamos para autenticación en enero de 2026, antes de la migración?"* — imposible con markdown o vectores.

### 4.3 Estructura de codebase para codebases grandes

A partir de ~200 archivos, Claude no puede "leer todo" para responder preguntas de arquitectura. Un grafo de AST (Tree-sitter) permite:
- Encontrar todos los callers de una función sin grep
- Calcular el "blast radius" de un cambio (qué módulos se ven afectados)
- Detectar dependencias circulares
- Navegar call graphs complejos

Para codebases de React con 500+ componentes o C++ con múltiples módulos interdependientes, Graphify reduce el contexto a lo que realmente importa.

---

## 5. Cuándo el markdown SÍ gana

### 5.1 Inspectabilidad y control humano

Un grafo en Neo4j o FalkorDB requiere Cypher o la UI del browser para inspeccionarlo. Un archivo markdown es legible en cualquier editor, versionable con git, debuggeable sin herramientas especializadas.

Si Claude te da una respuesta incorrecta basada en memoria: con markdown, abres el archivo y ves exactamente qué dato incorrecto tiene. Con un grafo, necesitas abrir el browser en `localhost:3000` y navegar el grafo.

### 5.2 Conocimiento estable y procedimental

Las convenciones del proyecto, los procedimientos de deploy, las preferencias de código — estos hechos cambian raramente. No necesitan timestamping temporal. Un archivo `dev-conventions.md` bien mantenido es suficiente y más rápido de consultar.

### 5.3 Colaboración y revisión humana

Los ADRs (Architecture Decision Records), las notas de proyecto, el diario de decisiones — estos documentos tienen valor más allá de la IA. Son documentación del equipo, revisable por humanos, compartible en PR reviews. Markdown en un vault de Obsidian sirve ambos propósitos simultáneamente.

### 5.4 Costo de mantenimiento bajo

Un vault de Obsidian con 500 notas es prácticamente libre de mantener. Una instancia de Neo4j o FalkorDB requiere Docker, persistencia, backups, y ocasionalmente mantenimiento de índices. Para un desarrollador individual, la carga operacional importa.

---

## 6. Graphify: el caso especial

Graphify merece análisis separado porque es fundamentalmente diferente a los demás sistemas de grafo:

### Qué hace diferente

```
Input:  código fuente (Python, JS/TS, C++, Dart, 36 lenguajes)
        + docs (Markdown, PDFs, imágenes, videos)
        
Proceso Pass 1: Tree-sitter AST → CERO tokens LLM
                (clases, funciones, imports, call graphs)
                
Proceso Pass 2: LLM semántico → solo para PDFs/imágenes/md (opcional)

Output: graph.json       (grafo consultable)
        GRAPH_REPORT.md  (resumen legible, Obsidian-compatible)
        graph.html       (visualización interactiva)
        cache/           (SHA256 por archivo, solo reprocesa cambios)
```

### Por qué 0 tokens en el caso de uso principal

El 95% del valor de Graphify viene del Pass 1 (AST estático). Para saber "¿qué archivos importan a AuthService?" no necesitas un LLM — es información estructural del código. Tree-sitter lo extrae en milisegundos sin llamar a ninguna API.

El GRAPH_REPORT.md que genera puede vivir en el vault de Obsidian, siendo accesible tanto para el desarrollador como para Claude vía el MCP de Obsidian.

### Integración con Obsidian

Desde la versión 0.5.0 (abril 2026), Graphify soporta export a Obsidian vault con links bidireccionales. El GRAPH_REPORT.md incluye `[[wikilinks]]` al estilo Obsidian, haciendo que el grafo del codebase sea navegable desde el vault como cualquier otra nota.

---

## 7. Decisión: la arquitectura en capas

La respuesta correcta no es "grafos o markdown" sino **"qué sistema para qué capa":

```
CAPA 1 — Estructura del codebase → Graphify (AST, 0 tokens)
  Pregunta: "¿Dónde está X? ¿Qué depende de Y?"
  Cuándo actualizar: post-commit (hook de git)
  
CAPA 2 — Conocimiento del proyecto → Obsidian vault (markdown)
  Pregunta: "¿Por qué se tomó esta decisión? ¿Cuál es la convención?"
  Cuándo actualizar: cuando Claude o el dev aprenden algo importante
  
CAPA 3 — Memoria temporal (opcional) → Graphiti + FalkorDB
  Pregunta: "¿Qué era verdad X días atrás? ¿Cómo evolucionó Y?"
  Cuándo usar: si tienes hechos que cambian y necesitas razonamiento temporal
  
CAPA 4 — Instrucciones de sesión → CLAUDE.md (< 500 tokens)
  Pregunta: "¿Qué debe saber Claude siempre, en cada sesión?"
  Cuándo actualizar: raramente, solo lo que no puede inferirse del código
```

Esta arquitectura en capas evita el error más común: intentar usar un solo sistema para todo y terminando con un sistema que hace todo mal.

---

*Siguiente: [Graphiti + FalkorDB: Memoria Temporal](./03-GRAPHITI-FALKORDB-MEMORIA-TEMPORAL.md)*
