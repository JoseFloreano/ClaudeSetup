---
name: project-resume
description: >
  Pone al día la sesión sobre un proyecto YA enganchado: lee su memoria durable
  antes de trabajar, para no empezar en frío. Use al INICIO de sesión o cuando
  el usuario dice "retomemos X", "sigamos con", "ponte al día", "qué teníamos
  pendiente", "resume this project", "catch up". Solo lee y orienta, no modifica
  nada. Si el proyecto no tiene carpeta en 10-Projects/, sugiere project-onboard.
---

# Project Resume

Carga el contexto durable de un proyecto existente al arrancar, para continuar
donde se quedó. **Solo lectura** — no escribe memoria en este paso.

## Requisitos

- Vault en `DevSetup/ObsidianVault/`, bajo OneDrive (multi-laptop) o bajo el
  home / `%USERPROFILE%` (single-laptop) — usa la raíz que exista. Si no hay
  vault, avísalo y sigue con lo que haya en el repo.
- MCP `graphiti-memory` — **opcional**: si no está, omite su búsqueda sin error
  (el vault es la fuente primaria).

## Pasos

1. Identifica el **proyecto activo**: de la sección "Active Project" del
   `CLAUDE.md`, o del nombre de la carpeta del repo. Respeta el aislamiento:
   solo este proyecto.
2. Lee `10-Projects/<nombre>/_PROJECT.md`. Si no existe, el proyecto no está
   enganchado → sugiere `project-onboard` y para. Si existe
   `codebase-map.md`, léelo también — es el mapa estructural del proyecto.
3. Lee los **últimos ~3 ADRs** de `10-Projects/<nombre>/ADRs/` (por la fecha del
   nombre, descendente) y revisa `bugs/` por issues abiertos relevantes a la
   tarea de hoy.
4. *(Solo si graphiti-memory está disponible)* `search_facts("recent decisions
   and known issues", group_ids=["<nombre>", "dev-global"])`. Si no está,
   omítelo en silencio.
5. **Resume al usuario** en pocas líneas: estado actual, decisiones clave, bugs
   conocidos y pendientes; pregunta en qué quiere continuar.
6. No modifiques nada aquí. Para guardar hallazgos usa `memory-keeper`; para
   decisiones de arquitectura, `adr-writer`.
