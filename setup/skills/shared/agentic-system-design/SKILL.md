---
name: agentic-system-design
description: >
  Diseña sistemas y automatizaciones con IA agéntica eligiendo el patrón mínimo
  que resuelve el problema: workflow determinista vs agente, sesión única vs
  subagents vs Agent Teams, y los 5 patrones canónicos de Anthropic. Use when
  the user says "diseña una automatización", "¿cómo estructuro este agente?",
  "¿subagents o un solo agente?", "multi-agente", "orquestación", "pipeline de
  agentes", or planea un sistema que usa LLMs para automatizar un proceso.
---

# Agentic System Design

Basada en "Building Effective Agents" (Anthropic) + docs oficiales de Agent
Teams. Principio rector: **el patrón más simple que funcione** — cada capa de
agencia añade costo, latencia y superficie de error.

## La escalera de decisión (subir solo si el escalón falla)

1. **Un solo LLM call** con buen prompt y retrieval — resuelve más de lo que parece.
2. **Workflow determinista** (código orquesta, LLM ejecuta pasos): para procesos
   con etapas conocidas. Patrones: *prompt chaining* (etapas secuenciales con
   validación entre pasos), *routing* (clasificar → delegar al manejador),
   *parallelization* (fan-out de subtareas independientes + agregación).
3. **Agente** (el LLM decide sus pasos): solo cuando el camino NO se conoce de
   antemano. Patrones: *orchestrator-workers* (uno descompone y delega),
   *evaluator-optimizer* (generador + crítico en loop).
4. **Multi-agente persistente** (Agent Teams): tareas largas con task list
   compartida y mensajería entre pares. El más caro — último recurso.

## Reglas de nuestro setup

- **Subagents vs Teams** (docs oficiales): subagents = reportan solo al
  principal, baratos, para paralelizar lecturas/tareas aisladas. Teams =
  task list compartida + mensajería, 3-5 miembros máx, file-ownership por
  miembro — solo para features largas multi-frente.
- **Dónde corre**: exploración/research paralelo → Cowork (workflows, sesión
  persistente); código sobre repo local → Claude Code (subagents/worktrees).
  Dos escritores sobre los mismos archivos: prohibido sin ownership (doc 12).
- **Costo primero**: estima tokens por corrida × frecuencia ANTES de construir.
  Un agente que corre 20×/día merece menos agencia y más workflow.
- **Enforcement determinista** donde importe (regla R2): validaciones y gates
  van en hooks/código, no en el prompt.

## Pasos

1. Define la tarea en una frase: entrada → salida → criterio de éxito medible.
2. Recorre la escalera: ¿por qué el escalón anterior no basta? Escríbelo — si
   no puedes justificarlo, baja un escalón.
3. Elige el patrón y dibuja el flujo (pasos, quién decide qué, dónde hay gates).
4. Modela el costo: tokens/corrida, frecuencia, modelo por etapa (barato para
   pasos mecánicos, caro solo donde se decide). Si aplica, usa `model-benchmark`
   para elegir modelo/proveedor por etapa.
5. Para decisiones de arquitectura disputadas → `council`; la decisión final →
   `adr-writer`.
6. Define la verificación del sistema: cómo sabrás que funciona (eval mínima,
   casos de prueba) ANTES de construirlo.

## Referencias

- Ensayo: anthropic.com/research/building-effective-agents (los 5 patrones)
- Agent Teams: code.claude.com/docs/en/agent-teams (límites y best practices)
