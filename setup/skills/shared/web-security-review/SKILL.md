---
name: web-security-review
description: >
  Revisa código web en busca de vulnerabilidades siguiendo OWASP Top 10 (inyección,
  XSS, control de acceso roto, autenticación débil, SSRF, deserialización insegura,
  configuración expuesta) y entrega hallazgos por severidad con fix mínimo. Use when
  the user says "revisa la seguridad", "security review", "¿esto es seguro?", "busca
  vulnerabilidades", "audita este endpoint/componente/PR", or before merging code that
  handles user input, auth, queries or file/URL access. Cubre React/Next, Node/Express
  y Python (Django/Flask/FastAPI); es agnóstica al framework cuando hace falta.
---

# Web Security Review

Auditoría defensiva de código web contra OWASP Top 10. Objetivo: encontrar
vulnerabilidades reales y explicarlas de forma accionable — no generar ruido.

## Cuándo usar

- Antes de mergear código que toca entrada de usuario, auth, queries, render o acceso a archivos/URLs.
- Cuando el usuario pide revisar la seguridad de un endpoint, componente, PR o módulo.

## Requisitos

- Solo lectura de código — funciona en Claude Code y en Cowork sin MCP.
- En Cowork: stage-a solo los archivos en alcance, no el repo completo.

## Pasos

1. **Delimita el alcance.** Un diff, un PR, un endpoint o un módulo — nunca "todo el
   repo" de una vez. Si es grande, pide priorizar por superficie de ataque.
2. **Mapea la superficie:** puntos de entrada de usuario, endpoints y sus params,
   queries a BD, render de HTML, límites de autenticación/autorización, llamadas a
   URLs/archivos externos, y configuración/secretos.
3. **Detecta el stack** (React/Next, Node/Express, Python) y recorre el checklist de
   `references/owasp-web-top10.md`, aplicando los patrones concretos de ese stack.
4. **Por cada hallazgo, documenta:** severidad (crítica / alta / media / baja),
   ubicación `archivo:línea`, un **escenario de explotación concreto** (input → efecto),
   y el **fix mínimo** con ejemplo de código corregido.
5. **Verifica de forma adversarial** antes de reportar: por cada hallazgo intenta
   refutarlo — ¿hay sanitización o validación aguas arriba?, ¿el input es realmente
   controlable por el atacante?, ¿el framework ya lo mitiga por defecto? Descarta lo
   que no sobreviva. Prefiere pocos hallazgos ciertos a muchos dudosos.
6. **Entrega** los hallazgos ordenados por severidad. Si no encontraste nada real,
   dilo claramente — no inventes vulnerabilidades para justificar la revisión.

## Qué NO hacer

- No escribas exploits funcionales dirigidos a sistemas de terceros; el objetivo es
  el fix, no el arma. Un PoC mínimo para demostrar el bug en el propio código está bien.
- No marques como vulnerabilidad lo que el framework ya mitiga por defecto sin evidencia
  de que se desactivó (p. ej. escaping de React, ORM parametrizado) — verifícalo primero.
- No reportes severidad inflada: calíbrala por impacto real y explotabilidad.

## Referencias

- `references/owasp-web-top10.md` — checklist OWASP Top 10 con patrones de código
  vulnerable y su fix por stack (React/Next, Node/Express, Python). Ábrelo al revisar.
