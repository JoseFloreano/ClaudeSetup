# API Design — Checklist operativo

Revisar ANTES de implementar y ANTES de publicar. Por stack al final.

## Recursos y URLs

- [ ] Sustantivos en plural, kebab/lowercase, sin verbos (`/user-profiles`, no `/getUserProfile`)
- [ ] Anidado máximo 2 niveles; más profundo → aplanar con filtros (`/payments?invoice_id=`)
- [ ] IDs opacos hacia afuera (UUID/ULID) — nunca autoincrementales expuestos (enumeración = IDOR fácil)
- [ ] Acciones no-CRUD como sub-recurso POST (`/orders/{id}/cancel`)

## Métodos y semántica

- [ ] GET sin efectos secundarios (cacheable); nunca mutar en GET
- [ ] PUT/DELETE idempotentes de verdad (repetir = mismo estado, mismo status o 404 tolerado)
- [ ] POST con `Idempotency-Key` donde el retry duele (pagos, creación de recursos caros)
- [ ] 201 + `Location` al crear; 204 sin body al borrar

## Errores

- [ ] Formato único problem+json: `{type, title, status, detail, code}` — el `code` propio es el contrato estable para clientes
- [ ] Mapa de status decidido: 400 malformado · 401 sin identidad · 403 sin permiso · 404 no existe (o existe pero no es tuyo — anti-enumeración) · 409 conflicto de estado · 422 semánticamente inválido · 429 rate limit (+`Retry-After`)
- [ ] Mensajes de error sin filtrar internals (stack traces, SQL, rutas)
- [ ] Validación de entrada en el borde con el schema (Pydantic/zod) — el handler recibe datos ya válidos

## Colecciones

- [ ] Paginación en TODA colección desde v1 (añadirla después es breaking)
- [ ] Cursor-based para datos que cambian (`?cursor=...&limit=`, respuesta con `next_cursor`)
- [ ] Límite máximo de page size impuesto en servidor
- [ ] Orden y filtros consistentes en toda la API (`?sort=-created_at&status=paid`)

## Seguridad (cruzar con authn-authz-review y web-security-review)

- [ ] Auth verificada en CADA endpoint (deny-by-default); ownership tras cargar el recurso
- [ ] Rate limiting al menos en auth y endpoints caros
- [ ] CORS explícito (nunca `*` con credenciales)
- [ ] Campos sensibles nunca en respuestas por accidente (allowlist de serialización, no blocklist)

## Contrato y consistencia

- [ ] OpenAPI/schema versionado en el repo ANTES de implementar (insumo de api-evolution)
- [ ] Convenciones globales escritas: snake_case vs camelCase en JSON (una, para siempre), timestamps ISO 8601 UTC, dinero en enteros de unidad mínima
- [ ] Campos de respuesta consistentes entre endpoints (el mismo `user` se ve igual en todos lados)
- [ ] Health check (`/healthz`) y versión (`/version`) para operación

## Por stack

**FastAPI:** modelos Pydantic v2 separados para request/response (nunca el modelo de DB directo); `response_model` siempre; routers por dominio; el OpenAPI que genera ES el contrato — revísalo, no lo ignores.

**Express:** validación con zod en middleware; error handler central que emite problem+json; `openapi.yaml` a mano o zod-to-openapi en CI.

**Next.js API routes / route handlers:** cada handler re-verifica auth (no confiar en el middleware de páginas); zod en el borde; los route handlers son API pública aunque "solo los use tu frontend" — mismo rigor.
