<!-- Snippet para el CLAUDE.md GLOBAL (~60 tokens).
     Superpowers respeta "user preferences" para la ubicación de specs/planes —
     verificado en sus SKILL.md de brainstorming y writing-plans (jul 2026).
     Con esto + la skill design-doc-harvest queda cerrado el ciclo de vida
     de los docs de diseño SIN forkear el plugin. -->

## Superpowers design docs

- Specs (brainstorming) y planes (writing-plans) van a `docs/superpowers/` del
  repo y son **documentos de trabajo TEMPORALES**, no memoria.
- Al terminar de implementar un plan, usa la skill `design-doc-harvest`:
  lo durable → ADR en el vault (via adr-writer); los docs de trabajo se borran
  (git conserva la historia).
