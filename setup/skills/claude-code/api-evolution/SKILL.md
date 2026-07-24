---
name: api-evolution
description: >
  Mantiene y evoluciona APIs existentes sin romper clientes: detecta breaking
  changes (oasdiff contra el OpenAPI versionado), aplica la política de
  deprecation y decide cuándo versionar. Use when the user says "cambia este
  endpoint", "¿esto rompe la API?", "depreca X", "saca la v2", "breaking
  change", or before merging any change that touches a published API surface.
  Para diseñar una API nueva usa api-design.
---

# API Evolution

Una API publicada es un contrato con clientes que no controlas (incluido tu
yo del futuro y tus apps móviles ya instaladas). Regla base: **aditivo =
gratis; breaking = versionar o deprecar con proceso.**

## Requisitos

- OpenAPI versionado en el repo (lo produce `api-design` paso 6). Sin él,
  primero generarlo del código actual — es el baseline.
- `oasdiff` instalado (`go install github.com/oasdiff/oasdiff@latest` o
  binario de releases) — si no está, haz el diff manual contra el checklist
  de abajo y dilo.

## Qué es breaking (memorízalo)

**Rompe:** quitar/renombrar endpoint, campo de respuesta o valor de enum;
volver requerido un parámetro opcional; cambiar tipo o formato de un campo;
endurecer validación; cambiar semántica de un status code; bajar límites.
**No rompe:** endpoint nuevo, campo de respuesta nuevo, parámetro opcional
nuevo, valor de enum nuevo SOLO en requests, relajar validación.

## Pasos

1. **Detecta**: con el cambio hecho, corre
   `oasdiff breaking openapi-base.yaml openapi-nuevo.yaml` (o
   `oasdiff changelog` para el detalle completo). Sin oasdiff: revisa el diff
   del spec contra la lista de arriba, campo por campo.
2. **Si es aditivo**: mergea, actualiza el OpenAPI versionado (nuevo baseline)
   y anota en el changelog de la API. Fin.
3. **Si es breaking, elige en este orden**:
   a) **Rediseñar como aditivo** (campo nuevo junto al viejo, endpoint
      paralelo) — casi siempre posible y siempre más barato.
   b) **Deprecar con proceso**: marca `deprecated: true` en el spec, header
      `Deprecation` + `Sunset` en las respuestas, documenta el reemplazo,
      y fija la ventana (regla práctica: 6 meses APIs públicas, 1-2 ciclos de
      release para apps móviles propias — los clientes viejos no se actualizan
      solos).
   c) **Versionar** (`/v2`) solo cuando los breaking se acumulan — cada
      versión viva es costo de mantenimiento doble; nunca más de 2 activas.
4. **Verifica clientes conocidos**: busca usos del campo/endpoint afectado en
   tus propios repos (frontend, apps Flutter) antes de confiar en que "nadie
   lo usa". Grep primero, confianza después.
5. **Registra**: breaking change o deprecation → ADR con `adr-writer`
   (qué, por qué, ventana, migración). El changelog de la API se actualiza
   SIEMPRE (aditivo incluido) — es el historial que tus clientes leen.
6. **Al cumplirse el sunset**: eliminar el código viejo es una tarea agendada,
   no un "algún día" — déjala en Pendientes del vault al deprecar.

## Qué NO hacer

- No "arreglar" nombres de campos publicados por estética — un rename es
  breaking sin valor para el cliente.
- No versionar por un solo breaking evitable (opción a primero).
- No deprecar sin `Sunset` fechado: deprecación sin fecha = para siempre.
