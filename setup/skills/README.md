# Skills Modulares — Carpeta única en OneDrive para Claude Code y Cowork

Sistema de skills compartido entre productos: **una carpeta en OneDrive es la fuente
de verdad**, y cada producto la consume por su mecanismo nativo. Añadir una skill
nueva = crear una carpeta + correr un script (o nada, si ya tienes el watcher).

## La estructura (fuente de verdad)

```
OneDrive/DevSetup/claude-skills/
├── shared/            ← skills que sirven a AMBOS productos
│   └── adr-writer/
│       └── SKILL.md
├── claude-code/       ← solo Claude Code (asumen terminal/toolchain local)
├── cowork/            ← solo Cowork (asumen sandbox cloud, documentos, web)
├── _template/         ← plantilla para crear skills nuevas
│   └── SKILL.md
└── _build/            ← generado por sync-skills (NO editar a mano)
    ├── dev-skills/    ← plugin para Cowork
    └── dev-skills.zip
```

Esta carpeta se crea automáticamente la primera vez que corres `sync-skills.ps1`
(seed desde `setup/skills/` del repo). OneDrive la replica a todas tus laptops.

## Cómo llega cada skill a cada producto

| Producto | Mecanismo | Qué recibe |
|----------|-----------|------------|
| Claude Code | `sync-skills.ps1/.sh` **copia** (nunca symlink — hallazgo H8) a `~/.claude/skills/` y a cada `~/.claude-*/skills/` (multi-cuenta) | `shared/` + `claude-code/` |
| Cowork | El mismo script empaqueta un plugin `dev-skills` (carpeta + .zip en `_build/`); lo instalas una vez en el desktop app: **Customize → Plugins → subir plugin** | `shared/` + `cowork/` |

El uso es **automático en ambos**: los dos productos descubren skills por
*progressive disclosure* — solo el `name` + `description` entran al contexto, y el
agente carga el cuerpo cuando la tarea coincide con la descripción. No hay que
invocarlas manualmente ni configurar nada más.

> **La descripción ES el trigger.** Una skill con mala descripción no se usa nunca.
> Ver reglas en `_template/SKILL.md`.

## Añadir una skill nueva (el flujo completo)

```
1. Copia _template/ →  shared/mi-skill/   (o claude-code/ o cowork/, según aplique)
2. Edita SKILL.md    →  name + description con triggers + cuerpo corto
3. Corre sync:
     Windows:      .\sync-skills.ps1
     macOS/Linux:  ./sync-skills.sh
4. Claude Code: la skill ya está (nueva sesión la ve).
   Cowork: re-sube _build/dev-skills.zip solo si la skill es shared/ o cowork/.
```

En las demás laptops: OneDrive sincroniza la carpeta sola; solo corre el paso 3.

## Reglas del sistema

1. **Kebab-case** en nombres de carpeta: `adr-writer`, no `ADR Writer`.
2. **Un `SKILL.md` por carpeta**, frontmatter YAML con `name` y `description` obligatorios.
3. **Cuerpo corto** (< 500 palabras). Material extenso va en archivos junto al
   SKILL.md (`references/`, `scripts/`) — el agente los lee solo si los necesita
   (progressive disclosure, mismo principio que CLAUDE.md < 500 tokens, hallazgo H4).
4. **Conflictos de nombre**: si una skill existe en `shared/` y en la carpeta de un
   producto, **gana la del producto** (es más específica). Evítalo de todas formas.
5. **Sin secretos**: las skills viajan por OneDrive y se empaquetan en plugins.
   API keys y rutas de máquina van en `.env` / settings, nunca en una skill.
6. **`_build/` es desechable**: lo regenera el script en cada corrida.

## Decidir en qué carpeta va una skill

| La skill... | Carpeta |
|-------------|---------|
| Solo describe metodología, formato o convenciones | `shared/` |
| Ejecuta comandos de tu toolchain local (flutter, cmake, docker, git hooks) | `claude-code/` |
| Depende de MCP en localhost sin fallback | `claude-code/` |
| Asume web research, documentos (docx/pptx/xlsx), sandbox cloud | `cowork/` |
| Usa el vault de Obsidian o Graphiti **con fallback documentado** | `shared/` (declara el fallback en la skill) |

## Verificar que funciona

- **Claude Code**: `ls ~/.claude/skills/` debe listar tus skills; en sesión, pide
  algo que coincida con la descripción y observa que la invoque.
- **Cowork**: en Customize → Plugins debe aparecer `dev-skills` con sus skills;
  igual — pide algo que coincida con un trigger.
