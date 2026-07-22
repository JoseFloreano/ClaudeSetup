# Graphiti + FalkorDB: Memoria Temporal con Grafo de Conocimiento
## Justificación técnica, arquitectura y hallazgos de implementación

---

## 1. Qué es Graphiti y por qué importa

Graphiti es un framework Python de código abierto (Apache 2.0) creado por el equipo de Zep AI. A diferencia de los sistemas RAG tradicionales que indexan documentos estáticos en lotes, Graphiti construye un **grafo de conocimiento temporal** que:

1. **Se actualiza en tiempo real** — cada episodio (conversación, decisión, hecho) se integra sin recomputación del grafo completo
2. **Preserva historia temporal** — los hechos tienen ventanas de validez (`valid_at / invalid_at`), no se sobreescriben sino que se invalidan
3. **Mantiene procedencia** — cada hecho traza su origen al episodio que lo produjo
4. **Soporta ontología prescrita y aprendida** — puedes definir tipos de entidad o dejar que emerjan del dato

### El problema que resuelve (que markdown no puede)

```
Sesión 1 (enero):  "Usamos Firebase para auth"
  → Markdown anota: auth = Firebase

Sesión 2 (marzo):  "Migramos de Firebase a Supabase"
  → Markdown: ¿crea duplicado? ¿sobreescribe? ambiguo

Sesión 3 (mayo):   "¿Qué auth usamos antes de Supabase?"
  → Markdown: no puede responder correctamente
  → Graphiti: "Firebase, válido de enero a marzo de 2026"
```

Esta capacidad de razonamiento temporal sobre hechos que cambian es lo que ningún sistema basado en markdown puede replicar de forma confiable.

---

## 2. Arquitectura interna de Graphiti

### Modelo de datos

```
EpisodicNode (input raw)
    │ extracción via LLM
    ▼
EntityNode (entidades extraídas)
    ├── name: "AuthService"
    ├── type: "CodeComponent"
    └── summary: "Maneja autenticación JWT"
    
EntityEdge (relaciones entre entidades)
    ├── fact: "AuthService usa Firebase para OAuth"
    ├── valid_at: 2026-01-15
    ├── invalid_at: 2026-03-20   ← invalida cuando cambia el hecho
    ├── created_at: 2026-01-15   ← cuándo el sistema supo del hecho
    └── embedding: [0.23, -0.41, ...]  ← para búsqueda semántica

CommunityNode (clusters de entidades relacionadas)
    └── summary: "Módulo de autenticación y sesiones"
```

### Retrieval sin LLM (el detalle más importante)

En búsqueda, Graphiti combina tres mecanismos **sin llamar al LLM**:

```
Query: "¿Qué auth usábamos antes de Supabase?"
    │
    ├── BM25 keyword search → "auth", "Supabase"
    ├── Vector semantic search → embeddings similares
    └── Graph traversal → nodos conectados a "auth"
    
    Fusión de resultados → P95 latencia: 300ms
```

El LLM solo se usa en la **escritura** (extracción de entidades al agregar un episodio), nunca en la lectura. Esto hace que el retrieval sea rápido y económico independientemente del volumen del grafo.

---

## 3. FalkorDB como backend: por qué sobre Neo4j

### Contexto

Graphiti soporta cuatro backends de base de datos:
- **FalkorDB** (default desde 2025) — Redis-based, en memoria, rápido
- **Neo4j** — el estándar enterprise de grafos
- **Kuzu** — embebido, sin servidor
- **Amazon Neptune** — managed cloud

### Por qué FalkorDB para uso personal/dev

El equipo de FalkorDB fue fundado por ex-Redis Graph. Sus benchmarks (auto-reportados, tomar con cautela) muestran:
- **496× mejor latencia P99** vs competidores en carga alta
- **6× mejor eficiencia de memoria**
- Consultas sub-10ms en grafos medianos

Para un desarrollador con 5-10 proyectos activos y sesiones de Claude Code diarias, FalkorDB en Docker es más que suficiente y significativamente más ligero que Neo4j (que requiere JVM y consume ~500MB solo para arrancar).

### Cuándo preferir Neo4j

- Equipos grandes con necesidades de grafos complejos
- Cuando ya tienes Neo4j en la stack
- Si necesitas el ecosistema enterprise de Neo4j (bloom, etc.)
- Producción con requerimientos de alta disponibilidad

---

## 4. Aislamiento multi-proyecto con group_id

### El problema que resolvió el PR #1209 (febrero 2026)

Antes del PR #1209, FalkorDB en Graphiti creaba una base de datos separada por cada `group_id`. Esto impedía queries cross-proyecto y complicaba la gestión de conocimiento compartido.

El PR unificó la arquitectura: **una sola base de datos `GRAPHITI`** con filtrado lógico por propiedad `group_id`, alineándose con el comportamiento de Neo4j.

### Modelo de aislamiento resultante

```
FalkorDB → base de datos "GRAPHITI"
    │
    ├── Nodos con group_id: "react-dashboard"
    │   └── decisiones, bugs, convenciones de ese proyecto
    │
    ├── Nodos con group_id: "flutter-app"
    │   └── decisiones, bugs, convenciones del app Flutter
    │
    ├── Nodos con group_id: "dev-global"
    │   └── preferencias del desarrollador, herramientas, workflow
    │
    └── Nodos con group_id: "dev-conventions"
        └── convenciones que aplican a todos los proyectos
```

Una consulta con `group_ids: ["flutter-app"]` devuelve solo los hechos de ese proyecto. Una consulta con `group_ids: ["flutter-app", "dev-global"]` combina el contexto del proyecto con las preferencias globales del desarrollador.

### El Smart Memory Writer (nuevo en PR #1209)

El PR también introdujo un clasificador LLM que automáticamente decide si un hecho nuevo va al grafo del proyecto o al grafo compartido, basado en análisis semántico. Esto evita el error más común: guardar convenciones personales en el grafo de un proyecto específico en vez del grafo global.

---

## 5. Configuración con Anthropic API (hallazgos específicos)

### El problema de structured output

Graphiti usa JSON schema para extraer entidades. Cada `add_episode` genera internamente prompts como:

```
Extrae las siguientes entidades de este texto:
{schema: {name: str, type: EntityType, description: str}}

Texto: "Decidimos usar Riverpod sobre Bloc porque..."
```

El modelo debe responder con JSON válido que coincida con el schema. Los modelos de OpenAI y Gemini tienen modo nativo de structured output (`response_format: {type: "json_schema"}`). Anthropic tiene un modo experimental.

**Resultado práctico**: con Anthropic (especialmente modelos pequeños como Haiku), hay una tasa mayor de fallos de JSON schema que resultan en errores de ingestion silenciosos — el episodio se guarda pero las entidades no se extraen correctamente.

**Recomendación de config**:

```yaml
# config.yaml — para mayor estabilidad
llm:
  provider: "openai"
  model: "gpt-4.1-mini"     # structured output nativo, barato
  small_model: "gpt-4.1-nano"

embedder:
  provider: "openai"
  model: "text-embedding-3-small"
```

Usar OpenAI para la extracción de entidades (escritura) no impide usar Claude Code (lectura/razonamiento) — son capas separadas. Claude Code sigue siendo el agente principal; Graphiti solo usa el LLM internamente para indexar el conocimiento.

---

## 6. El flujo completo de un episodio

```
1. Claude Code trabaja en un proyecto
       │
       ▼
2. Al final de la sesión (o cuando detecta información importante):
   add_episode(
     name="Decisión: migración a Supabase",
     episode_body={...},
     group_id="react-dashboard"
   )
       │
       ▼
3. Graphiti MCP Server recibe el episodio
       │ (proceso asíncrono, ~25 segundos)
       ▼
4. LLM extrae entidades:
   - EntityNode: "Supabase" (type: Library)
   - EntityNode: "Firebase" (type: Library, invalidated)
   - EntityEdge: "Supabase reemplaza Firebase para auth" (valid_at: hoy)
       │
       ▼
5. FalkorDB almacena el grafo actualizado
       │ (datos en disco local o en OneDrive vía bind mount)
       ▼
6. Próxima sesión: Claude busca antes de trabajar
   search_facts(
     query="autenticación y estado actual",
     group_ids=["react-dashboard", "dev-global"]
   )
       │ (retrieval: BM25 + vector + graph, <300ms)
       ▼
7. Claude recibe contexto relevante sin leer todos los archivos
```

---

## 7. Hallazgos sobre costos reales

### Costo de escritura con OpenAI gpt-4.1-mini

```
Episodio promedio: ~500 palabras de contexto
Extracción de entidades: ~1-3 llamadas internas al LLM
Tokens por episodio: ~1,500–3,000 input + ~200–500 output
Costo con gpt-4.1-mini: ~$0.001–0.003 por episodio

Con 10 episodios por sesión de trabajo:
→ ~$0.01–0.03 por sesión
→ ~$0.30–0.90 por mes con uso intensivo
```

Esto es económicamente negligible comparado con el costo de Claude Code en sí.

### Cuándo el costo escala problemáticamente

- Si cada turno de conversación genera un episodio (no recomendado — solo guardar hechos durable)
- Si SEMAPHORE_LIMIT es alto y el rate tier de API es bajo → errores 429
- Si los episodios son muy largos (>2,000 palabras cada uno)

**Práctica recomendada**: guardar episodios al **final** de la sesión o cuando Claude detecta una decisión importante, no en cada turno.

---

## 8. Limitaciones documentadas

| Limitación | Impacto | Mitigación |
|------------|---------|------------|
| `add_episode` asíncrono (~25s) | Los hechos no aparecen en search inmediatamente | Esperar 30s antes de buscar un episodio recién guardado |
| Structured output inestable con Anthropic pequeño | Entidades no extraídas correctamente | Usar OpenAI/Gemini para extracción |
| add_episode requiere formato string o dict | Dicts se pasan directo desde PR que añade auto-serialización JSON | Usar dicts para datos estructurados |
| group_id incorrecto contamina otro proyecto | Datos de Proyecto A aparecen en búsquedas de Proyecto B | Instrucción explícita en CLAUDE.md: nunca omitir group_id |
| Historial temporal puede crecer indefinidamente | Uso de disco creciente | Estrategia de archivado periódico (no documentada aún por Zep) |
| MCP en estado "experimental" | API puede cambiar en releases futuros | Fijar versión de imagen Docker en docker-compose.yml |

---

## 9. Cuándo NO usar Graphiti

Graphiti **no está justificado** si:

- Solo tienes 1-2 proyectos pequeños con pocos archivos
- No necesitas razonamiento temporal (la mayoría de los casos de dev personal)
- La complejidad operacional (Docker, FalkorDB, backups) excede el beneficio
- Tu stack de proyectos cambia poco y el contexto cabe en un CLAUDE.md bien estructurado
- Tienes Tier 1 de Anthropic API y el costo de escritura te preocupa

En esos casos, **Obsidian + Graphify** (sin Graphiti) es suficiente y mucho más simple.

---

*Siguiente: [OneDrive: Estrategias de Sincronización](./04-ONEDRIVE-SINCRONIZACION-MULTI-LAPTOP.md)*
