---
name: context-engineering
description: >
  Diseña el contexto de una automatización o agente: system prompts a la
  altitud correcta, qué entra a la ventana y qué se recupera bajo demanda, y
  técnicas para sesiones largas (compaction, notas externas, subagents). Use
  when the user says "arma el system prompt", "diseña el contexto", "context
  engineering", "el agente pierde el hilo", "se degrada en sesiones largas",
  "automatización de puro prompt", or junto con agentic-system-design al
  diseñar cualquier automatización — incluidas las que son SOLO un system
  prompt bien hecho.
---

# Context Engineering

Doctrina base (Anthropic, "Effective context engineering for AI agents"):
**el contexto es un recurso finito con rendimientos decrecientes** (context
rot). El trabajo no es escribir prompts largos — es curar el conjunto mínimo
de tokens de alta señal para cada momento. Nuestro setup entero ya lo aplica:
CLAUDE.md <500 (H4), skills con progressive disclosure, vault como memoria
externa, pocos MCPs (H3). Esta skill lo aplica a lo que TÚ construyas.

## Caso 1 — Automatización de puro system prompt (sin agencia)

El escalón 1 de `agentic-system-design`: muchas automatizaciones no necesitan
tools ni loops — necesitan un system prompt bien diseñado y ya. Usa la anatomía
de `references/system-prompt-blueprint.md` (rol y altitud, reglas duras POCAS,
workflow, contrato de salida, 1-3 ejemplos canónicos, conducta ante fallo).
Regla de altitud: ni lógica hardcodeada frágil (if-else en prosa) ni vaguedad
("sé útil") — heurísticas fuertes + criterios de éxito.

## Caso 2 — Contexto de un agente/automatización con tools

1. **Presupuesto primero**: ¿qué DEBE estar siempre en contexto? (rol, reglas,
   contrato). Todo lo demás se recupera just-in-time (retrieval, archivos,
   skills) — precargar "por si acaso" es el anti-patrón dump (doc 06).
2. **Tools mínimas y sin solape**: cada tool con propósito único y descripción
   que diga cuándo usarla; si dos tools compiten por el mismo caso, el agente
   elegirá mal (mismo principio que triggers de skills).
3. **Ejemplos: pocos y canónicos** — 1-3 que muestren el caso típico + el edge
   más importante. Nunca listas exhaustivas de reglas-por-ejemplo.

## Caso 3 — Horizonte largo (el agente pierde el hilo)

Tres técnicas oficiales, en orden de costo:
- **Compaction**: resumir-y-continuar en fronteras de fase, no a mitad de una
  tarea; preservar decisiones/estado, tirar resultados de tools viejos.
- **Notas estructuradas** (memoria externa): estado durable FUERA de la
  ventana que se relee al retomar — nuestro `_PROJECT.md` + pendientes ES este
  patrón; para tus automatizaciones: un archivo de estado propio (qué va, qué
  falta) que la automatización actualiza y relee.
- **Subagents**: exploración/trabajo sucio en contexto ajeno; al principal
  solo vuelve el destilado.

## Verificación

Antes de dar por bueno el diseño: (a) ¿cada bloque del contexto justifica sus
tokens? (b) ¿qué pasa en el turno 50 — qué creció sin límite?; (c) prueba de
degradación: corre el caso típico con el contexto lleno de ruido realista y
compara. Si diseñaste un sistema completo, cierra con `adr-writer`.

## Referencias

- `references/system-prompt-blueprint.md` — anatomía + checklist + plantilla
  para automatizaciones de puro prompt.
