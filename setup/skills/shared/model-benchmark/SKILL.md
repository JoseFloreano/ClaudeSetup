---
name: model-benchmark
description: >
  Compara modelos y proveedores de LLM para un caso de uso concreto usando
  fuentes vivas (precios, benchmarks agénticos, costo-por-tarea) y entrega una
  recomendación con números. Use when the user says "qué modelo uso para X",
  "compara modelos/proveedores", "cuánto costaría con Y", "benchmark de
  modelos", "¿gemini o groq o gpt?", or when choosing the LLM for a pipeline,
  extraction job, or automation stage.
---

# Model Benchmark

Regla de oro: **$/Mtoken es marketing; costo-por-TAREA es la métrica** — un
modelo barato por token que necesita más turnos/retries sale caro. Siempre con
datos del día (los precios y rankings cambian cada mes — H10: no confiar en
memoria ni en números de vendors sin verificar).

## Requisitos

- Acceso a web (WebSearch/WebFetch). Sin red: dilo y no inventes precios.

## Fuentes vivas (en este orden)

| Fuente | Qué da | Acceso |
|--------|--------|--------|
| artificialanalysis.ai | Intelligence Index, velocidad, **Cost per Task** | Web gratis |
| openrouter.ai/api/v1/models | Precios unificados de TODOS los proveedores | API pública sin auth |
| arena.ai/leaderboard | Elo humano por categoría (coding, web, visión) | Gratis |
| swebench.com · tbench.ai | Benchmarks agénticos (código, terminal) | Gratis |
| Docs oficiales del proveedor | Precio de verdad + límites de rate/free tier | Gratis |

## Pasos

1. **Define la tarea y su perfil**: ¿qué hace? (extracción, código, chat,
   clasificación), tokens típicos in/out por corrida, corridas/mes, ¿necesita
   structured output/tool use/visión?, ¿latencia importa?
2. **Preselecciona 3-5 candidatos** por perfil (no compares 20): al menos un
   frontier, un mid-tier y un budget/free-tier.
3. **Trae los datos del día**: precios (OpenRouter API + docs oficiales),
   calidad en el benchmark que corresponde al perfil (SWE-bench para código,
   Terminal-Bench para agentes de terminal, arena.ai para calidad general),
   y free tiers con sus límites REALES (RPM/TPM/RPD — el cuello suele estar
   en TPM, no en requests: caso Groq 6k TPM).
4. **Calcula costo-por-tarea**:
   `(input_no_cacheado × $in + cache_reads × ~0.1×$in + output × $out) × turnos × (1 + tasa_retry)`
   × corridas/mes = costo mensual por candidato. Muestra la fórmula con los
   números, no solo el resultado.
5. **Entrega tabla comparativa** (candidato, calidad en el benchmark relevante,
   $/tarea, $/mes, límites, riesgos) + recomendación con su segundo lugar y el
   criterio de cambio ("si el volumen supera X, cambia a Y").
6. Si la elección es para una pieza del setup (p.ej. extracción de Graphiti),
   registra la decisión con `adr-writer` incluyendo los números del día — el
   ADR con fecha es lo que permite re-evaluar cuando cambien los precios.

## Qué NO hacer

- No cites benchmarks de un solo vendor como verdad (H10) — cruza mínimo 2 fuentes.
- No recomiendes por Elo general algo que se usará para una tarea específica.
- No ignores el costo de cache/razonamiento en modelos con thinking.
