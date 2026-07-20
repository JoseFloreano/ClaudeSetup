---
name: authn-authz-review
description: >
  Revisa a fondo autenticación y autorización web: manejo de sesiones y cookies, JWT,
  almacenamiento de contraseñas, flujos de login/reset/MFA y control de acceso
  (RBAC, ownership, IDOR). Use when the user says "revisa el login/auth", "el control
  de acceso", "permisos", "revisa el JWT", "las sesiones", "¿puede un usuario ver datos
  de otro?", or when reviewing an auth flow or endpoint. Cubre React/Next, Node/Express
  y Python (Django/Flask/FastAPI).
---

# Authn / Authz Review

Revisión especializada de identidad y acceso (OWASP A01 y A07) — la superficie donde
un bug equivale a bypass total. Solo lectura; enfócate en el límite de confianza.

## Requisitos

- Solo lectura de código — funciona en Claude Code y en Cowork sin MCP.
- En Cowork: stage-a solo el módulo de auth y los endpoints en alcance.

## Pasos

1. **Ubica el límite de confianza:** dónde se autentica (login, middleware, guard) y
   dónde se autoriza (por endpoint/acción/recurso). Toda ruta protegida debe pasar por ahí.
2. Recorre el checklist de `references/auth-checklist.md` para el stack detectado.
3. **Prueba mentalmente los abusos clave:** ¿puede el usuario A leer/editar el recurso de
   B cambiando un `id`? (IDOR) · ¿la autorización se hace en el cliente y no se re-verifica
   en el servidor? · ¿un rol bajo alcanza una acción de admin por una ruta no guardada?
4. **Por cada hallazgo:** severidad, `archivo:línea`, escenario de explotación concreto
   (petición → acceso indebido) y fix mínimo con ejemplo.
5. **Verifica de forma adversarial:** confirma que no hay un guard aguas arriba (middleware,
   decorador, política) que ya lo cubra antes de reportar.
6. **Entrega** por severidad. Auth roto = normalmente crítico/alto: calíbralo así.

## Focos que no se deben omitir

- **Control de acceso (A01):** verificar *ownership* tras cargar el recurso, no solo
  autenticación; autorización server-side siempre; deny-by-default en rutas nuevas.
- **Sesiones/cookies:** `HttpOnly` + `Secure` + `SameSite`; rotar el id de sesión tras
  login; expiración e invalidación en logout.
- **JWT:** rechazar `alg:none`, validar firma y `exp`/`aud`/`iss`, secreto fuerte desde
  entorno; no guardar datos sensibles en el payload (es legible).
- **Contraseñas:** `bcrypt`/`argon2`/`scrypt`, nunca hash rápido ni texto plano; rate
  limit en login; reset con token aleatorio y de un solo uso con expiración.
- **MFA** donde el riesgo lo amerite.

## Referencias

- `references/auth-checklist.md` — checks detallados de sesiones, JWT, control de acceso
  y flujos, con patrón vulnerable → fix por stack. Ábrelo al revisar.
