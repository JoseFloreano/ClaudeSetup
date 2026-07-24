# System Prompt Blueprint — automatizaciones de puro prompt

Anatomía en 6 bloques, en este orden. Presupuesto total orientativo: 300-800
tokens (una automatización que necesita más, probablemente necesita retrieval
o una skill, no más prosa).

## 1. Rol y altitud (2-4 líneas)

Quién es y qué produce. La "altitud correcta": heurísticas fuertes, no
micro-instrucciones ni vaguedad.

- MAL (bajo): "Si el texto tiene más de 3 párrafos y menciona fechas, entonces..."
- MAL (alto): "Eres un asistente útil que ayuda con correos."
- BIEN: "Clasificas correos de soporte por urgencia e intención. Priorizas
  señales de pérdida de datos o dinero por encima del tono del cliente."

## 2. Reglas duras (3-7 máximo)

Solo lo innegociable. Cada regla extra diluye las demás (compliance se degrada
con el volumen — H4). Si acumulas >10 reglas, la automatización pide ser
workflow con validación en código, no prompt.

## 3. Workflow (pasos numerados)

El proceso en 3-7 pasos imperativos. Si un paso tiene sub-lógica compleja,
esa lógica va en código (escalón 2 de agentic-system-design), no en el prompt.

## 4. Contrato de salida

Formato EXACTO de la respuesta: schema JSON (con structured output del
proveedor si existe), plantilla markdown, o enum de valores permitidos.
La ambigüedad de salida es la causa #1 de automatizaciones frágiles.

## 5. Ejemplos canónicos (1-3)

Uno típico + el edge case más costoso. Formato entrada→salida completo.
Nunca uses ejemplos para colar reglas nuevas — si la regla importa, va al
bloque 2.

## 6. Conducta ante fallo

Qué hacer cuando no puede cumplir: valor de escape explícito
(`"confidence": "low"`, categoría `OTRO`, "escalar a humano") y la prohibición
de inventar. Toda automatización sin ruta de fallo definida alucina la salida.

---

## Checklist final

- [ ] ¿Cada bloque justifica sus tokens? (borra lo que no cambie el output)
- [ ] ¿El contrato de salida es parseable por código sin regex heroicos?
- [ ] ¿Probaste con 3+ entradas reales, incluida una basura/adversarial?
- [ ] ¿La ruta de fallo se dispara cuando debe (probaste una entrada imposible)?
- [ ] ¿Qué modelo lo corre y por qué? (perfil de la tarea → `model-benchmark`;
      para clasificación/extracción suele ganar un modelo chico con buen prompt)
- [ ] Si corre N veces/día: costo mensual estimado con la fórmula de
      `model-benchmark` §4.

## Plantilla

```
Eres [rol]. [Qué produces y para quién, 1-2 líneas de contexto].

Reglas:
1. [innegociable]
2. [innegociable]
3. Si no puedes cumplir con confianza, responde [valor de escape]. Nunca inventes.

Proceso:
1. [paso]
2. [paso]
3. [paso]

Responde ÚNICAMENTE con este formato:
[schema/plantilla exacta]

Ejemplos:
[entrada] → [salida]
[entrada edge] → [salida]
```
