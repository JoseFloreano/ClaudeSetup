<!-- Insertar en el CLAUDE.md del proyecto. ~230 tokens (H4).
     Reemplaza TODAS las apariciones de <project-name> por el nombre real.
     ⚠ COPIA SINCRONIZADA de setup/memory-instructions.md — si editas una,
     actualiza la otra (mismo contenido, dos puntos de consumo). -->

## Active Project: `<project-name>`   ← reemplazar al copiar

## Memory Rules — NON-NEGOTIABLE (anti cross-project hallucination)

1. Graphiti searches: ALWAYS `group_ids: ["<project-name>", "dev-global"]`.
   Never omit, never broaden, never `"main"`.
2. `add_episode`: ALWAYS `group_id: "<project-name>"`.
   Personal/cross-stack preferences → `"dev-global"`. Unsure → ask, don't guess.
3. Vault: only `10-Projects/<project-name>/`, `brain/`, `daily/`.
   Other projects' folders are OFF-LIMITS unless the user explicitly asks.
4. Memory from another project seems relevant → say so and ask; never import silently.
5. Stored fact contradicts current code/user → trust the present, update the memory.

At session start: `search_facts("recent decisions and known issues", group_ids=["<project-name>", "dev-global"])`, then read `10-Projects/<project-name>/_PROJECT.md`.

When saving decisions/bugs/conventions → use the `memory-keeper` skill (format & criteria live there). Architecture decisions → `adr-writer` skill.

If the `graphiti-memory` MCP is unavailable, skip Graphiti silently — the vault is the primary record.
