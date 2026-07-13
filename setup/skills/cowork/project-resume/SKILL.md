---
name: project-resume
description: >
  (Variante Cowork) Pone al día la sesión sobre un proyecto YA enganchado
  leyendo su memoria durable del vault de Obsidian conectado, para no empezar
  en frío. Use al INICIO de una sesión de Cowork sobre un proyecto, o cuando el
  usuario dice "retomemos X", "sigamos con", "ponte al día", "qué teníamos
  pendiente", "resume this project", "catch up". Solo lee y orienta, no
  modifica nada. Si el proyecto no tiene carpeta en 10-Projects/, dilo — el
  alta (project-onboard) se hace desde Claude Code.
---

# Project Resume (Cowork)

Carga el contexto durable de un proyecto existente al arrancar una sesión de
Cowork. **Solo lectura** — no escribe memoria ni commitea nada en este paso.

## Requisitos

- Carpeta del vault conectada a la sesión (`ObsidianVault/` o al menos
  `10-Projects/<proyecto>/`). Si no está conectada, PARA y pide al usuario
  conectarla con "Add folder" — sin vault no hay memoria que retomar.
- MCP `graphiti-memory` — **opcional** (solo existe vía puente del desktop
  app): si no está, omite su búsqueda en silencio; el vault es la fuente primaria.

## Pasos

1. Identifica el **proyecto activo**: de la sección "Active Project" de las
   instrucciones del proyecto de Cowork, o pregunta. Respeta el aislamiento:
   solo lee `10-Projects/<nombre>/` — carpetas de otros proyectos están
   OFF-LIMITS.
2. Stage-a y lee `10-Projects/<nombre>/_PROJECT.md` desde la carpeta conectada.
   Si no existe, el proyecto no está enganchado → sugiere correr
   `project-onboard` desde Claude Code y para.
3. Lista `ADRs/` y stage-a los **últimos ~3** (por la fecha `ADR-YYYYMMDD-*` en
   el nombre, descendente); revisa `bugs/` por issues abiertos relevantes.
   Stage-a solo lo que vas a leer — no la carpeta completa (anti-patrón de dump).
4. *(Solo si graphiti-memory está disponible)* `search_facts("recent decisions
   and known issues", group_ids=["<nombre>", "dev-global"])`.
5. **Resume al usuario** en pocas líneas: estado actual, decisiones clave, bugs
   conocidos y pendientes; pregunta en qué quiere continuar.
6. No modifiques nada aquí. Hallazgos → `memory-keeper`; decisiones →
   `adr-writer`; y recuerda que en Cowork todo cambio al vault debe
   **commitearse de vuelta** a la carpeta conectada al final.
