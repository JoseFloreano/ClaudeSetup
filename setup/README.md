# Graphiti + FalkorDB — Setup Multi-Laptop con OneDrive

Setup de memoria temporal con grafo de conocimiento para Claude Code,
diseñado para funcionar en 2-3 laptops sincronizadas via OneDrive.

## Arquitectura

```
Claude Code (laptop 1/2/3)
      │ HTTP MCP
      ▼
Graphiti MCP Server (:8000)   ◄── extrae entidades con LLM en escritura
      │
      ▼
FalkorDB (:6379)               ◄── grafo temporal persistente
      │
      ▼
/var/lib/falkordb/data/        ◄── volumen Docker
      │
      ├── dump.rdb             ← snapshot periódico (para backups a OneDrive)
      └── appendonly.aof       ← WAL para durabilidad máxima
```

## ⚠️ El problema real de OneDrive + FalkorDB

FalkorDB (basado en Redis) mantiene **locks activos** sobre `dump.rdb`
y `appendonly.aof` mientras está corriendo. OneDrive en Windows intenta
sincronizar archivos abiertos y puede generar:

- Corrupción del RDB si OneDrive interrumpe una escritura mid-snapshot
- Conflictos de sync si dos laptops tienen el container corriendo simultáneamente
- Locks que bloquean la sync de OneDrive silenciosamente

### Estrategia A — Recomendada: Datos locales + backups a OneDrive

```
FALKORDB_DATA_PATH=./data         # disco local, rápido, sin conflictos
backup-graph.sh cada 4 horas     # copia dump.rdb a OneDrive
Al cambiar de laptop:
  docker compose stop             # fuerza BGSAVE final
  backup-graph.sh                 # copia a OneDrive
  En laptop nueva: setup-new-machine.sh (restaura desde .rdb)
```

**Pros**: Sin riesgo de corrupción, rendimiento máximo, sync sin conflictos.
**Contras**: El grafo no se sincroniza en tiempo real entre laptops.

### Estrategia B — Datos en OneDrive (solo si un laptop a la vez)

```
FALKORDB_DATA_PATH=/ruta/onedrive/graphiti-data/falkordb
```

Requiere protocolo estricto:
- Solo UN container activo por vez
- Antes de cambiar: `docker compose stop graphiti-falkordb`
- Esperar a que OneDrive sincronice (verificar ícono sin conflictos)
- En nueva laptop: `docker compose up -d`

**Pros**: Sync automático del grafo completo.
**Contras**: Riesgo de corrupción si se olvida el protocolo.

### Estrategia C — FalkorDB Cloud (la más limpia para multi-laptop)

```yaml
# En .env:
# FALKORDB_URI=falkor://tu-instancia.falkordb.cloud:6379
# No necesitas Docker para FalkorDB — solo para el MCP server
```

FalkorDB Cloud es la opción recomendada por su equipo para acceso
multi-dispositivo. El MCP server sigue corriendo localmente en Docker,
pero se conecta a la instancia cloud en vez de localhost.

**Pros**: Grafo siempre disponible desde cualquier laptop, sin sync manual.
**Contras**: Requiere cuenta, tiene costo en volumen alto.

## Estructura de archivos en OneDrive

```
OneDrive/
└── DevSetup/
    ├── claude-dotfiles/          # repo git (configs de Claude Code)
    │   └── graphiti/
    │       ├── docker-compose.yml
    │       ├── config.yaml
    │       └── scripts/
    ├── graphiti-docker/          # directorio de trabajo Docker
    │   ├── docker-compose.yml   # (copiado desde dotfiles)
    │   └── .env                 # API keys (NO en git)
    └── graphiti-data/
        ├── falkordb/            # datos del grafo (Estrategia B)
        │   ├── dump.rdb
        │   └── appendonly.aof
        ├── backups/             # snapshots con timestamp (Estrategia A)
        │   ├── graphiti_20260712_120000.rdb
        │   └── graphiti_20260712_120000.manifest.json
        └── config/
            └── config.yaml
```

## Aislamiento multi-proyecto con group_id

Graphiti usa `group_id` para aislar la memoria entre proyectos en la
misma instancia de FalkorDB. Desde PR #1209, FalkorDB usa una única
base de datos `GRAPHITI` con filtrado por `group_id`:

```
FalkorDB (una sola BD: "GRAPHITI")
├── group_id: "react-dashboard"    → memoria del proyecto React
├── group_id: "flutter-app"        → memoria del proyecto Flutter
├── group_id: "python-api"         → memoria del proyecto Python
├── group_id: "dev-global"         → preferencias globales del dev
└── group_id: "dev-conventions"    → convenciones compartidas
```

En CLAUDE.md de cada proyecto añadir:
```markdown
## Memory
- Always use group_id: "nombre-proyecto" for project-specific memory
- Use group_id: "dev-global" for personal preferences and conventions
- Search before saving: call search_facts first
```

## Configuración de Claude Code

### MCP (scope user — aplica a todos los proyectos)
```bash
claude mcp add --transport http graphiti-memory http://localhost:8000/mcp/ -s user
```

### Verificar
```bash
claude mcp list
# graphiti-memory: http://localhost:8000/mcp/ (http)
```

### .graphiti.json por proyecto
Copia `config/graphiti-project-template.json` a la raíz de cada
proyecto como `.graphiti.json` y ajusta `project_id` y `group_id`.

El archivo es detectado vía `GRAPHITI_PROJECT_DIR` env var (no por CWD).
En Claude Code, configura esto en el hook SessionStart o en .env del proyecto.

## Caveats importantes

1. **Structured output con Anthropic**: Graphiti usa JSON schema para
   extraer entidades. Anthropic tiene soporte experimental — puede fallar
   con haiku o en prompts complejos. Usar OpenAI (gpt-4.1-mini) o Gemini
   para el LLM de extracción es más estable.

2. **add_episode es asíncrono**: El episodio se encola y procesa en ~25s.
   Los hechos no aparecen en search_facts inmediatamente tras add_episode.

3. **Costo de escritura**: Cada add_episode llama al LLM para extraer
   entidades (~1-3 llamadas internas). Con SEMAPHORE_LIMIT=3 y uso intenso
   puedes consumir bastante de tu rate limit. Monitoriza en el dashboard.

4. **No confundir con Graphify**: Graphiti = memoria de sesiones (qué se
   decidió, qué se aprendió). Graphify = estructura del codebase (qué
   función llama a qué). Son complementarios, no reemplazos.

5. **Recuperación de .rdb**: Si el grafo se corrompe o pierdes datos,
   restaurar desde backup: `docker cp backup.rdb container:/var/lib/falkordb/data/dump.rdb`
   luego `docker restart graphiti-falkordb`.

## Comandos útiles

```bash
# Levantar / bajar
docker compose up -d
docker compose stop     # guarda correctamente antes de apagar

# Ver logs
docker logs graphiti-mcp-server -f
docker logs graphiti-falkordb -f

# Backup manual
./scripts/backup-graph.sh ~/OneDrive

# Verificar grafo en FalkorDB Browser
open http://localhost:3000

# Ver tamaño del grafo
docker exec graphiti-falkordb redis-cli DBSIZE
docker exec graphiti-falkordb redis-cli INFO memory | grep used_memory_human

# Limpiar grafo de un proyecto (irreversible)
# docker exec graphiti-falkordb redis-cli DEL "graphiti:group_id:nombre-proyecto"

# Verificar MCP desde Claude Code
claude mcp list
```
