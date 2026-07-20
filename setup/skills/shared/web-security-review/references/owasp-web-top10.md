# OWASP Top 10 (2021) — Checklist web con patrones por stack

Referencia de `web-security-review`. Para cada categoría: qué buscar, patrón
vulnerable y fix. Los ejemplos son ilustrativos — adapta al código real.

---

## A01 — Broken Access Control

Qué buscar: endpoints sin verificar propiedad del recurso (IDOR), autorización
en el cliente en vez del servidor, rutas admin sin guard, `id` tomado del request
sin comprobar que pertenece al usuario autenticado.

- **Node/Express:** `app.get('/api/orders/:id', (req,res)=> db.order(req.params.id))` sin
  chequear `order.userId === req.user.id`. → Fix: verificar ownership tras cargar el recurso.
- **Django:** `Order.objects.get(pk=pk)` sin `filter(user=request.user)`. → Fix:
  `get_object_or_404(Order, pk=pk, user=request.user)`.
- **Next.js:** confiar en ocultar un botón en el cliente; el `route handler`/`API route`
  debe re-verificar rol y ownership en el servidor.

## A02 — Cryptographic Failures

Qué buscar: contraseñas sin hash o con MD5/SHA1, secretos hardcodeados, TLS
desactivado, JWT firmado con `none` o secreto débil, datos sensibles en logs.

- Passwords → `bcrypt`/`argon2`/`scrypt`, nunca hash rápido ni texto plano.
- No `Math.random()` para tokens; usa CSPRNG (`crypto.randomBytes`, `secrets`).
- JWT: rechazar `alg: none`; secreto largo desde entorno, no en código.

## A03 — Injection (SQLi, XSS, command, path traversal)

**SQLi** — concatenación de input en queries:
- **Node:** `db.query('SELECT * FROM u WHERE e = "'+email+'"')` → parametrizado:
  `db.query('SELECT * FROM u WHERE e = ?', [email])`.
- **Python:** f-strings en SQL crudo → usa ORM o `cursor.execute(sql, (param,))`.

**XSS** — render de input sin escapar:
- **React:** `dangerouslySetInnerHTML={{__html: userInput}}` → evítalo; si es
  imprescindible, sanitiza con DOMPurify. El JSX normal ya escapa.
- **Express + plantillas:** desactivar autoescape o `res.send('<div>'+input+'</div>')`.
- **Django/Jinja:** `|safe` o `mark_safe(user_input)` sobre datos del usuario.

**Command injection:** `exec`/`os.system`/`child_process.exec` con input → usa APIs
con args en array (`execFile`, `subprocess.run([...], shell=False)`).

**Path traversal:** `fs.readFile(baseDir + req.query.file)` con `../../` → normaliza y
valida que la ruta resuelta siga dentro de `baseDir`.

## A04 — Insecure Design

Qué buscar: falta de rate limiting en login/OTP, recuperación de cuenta débil,
flujos sin límites de negocio (compras con precio del cliente). Modela el abuso,
no solo el bug. Sugiere controles: rate limit, límites de cuota, validación server-side
de montos/estados.

## A05 — Security Misconfiguration

Qué buscar: `DEBUG=True` en prod, stack traces expuestos, CORS `*` con credenciales,
directorios/listados abiertos, headers de seguridad ausentes.

- CORS: `Access-Control-Allow-Origin: *` junto con `credentials: true` es inválido/peligroso.
- Headers recomendados: `Content-Security-Policy`, `Strict-Transport-Security`,
  `X-Content-Type-Options: nosniff`, `X-Frame-Options`/frame-ancestors.
- Next.js: revisar `headers()` en `next.config`; Express: `helmet`.

## A06 — Vulnerable and Outdated Components

Dependencias con CVEs conocidos. (Ver skill `dependency-audit` para el escaneo
automatizado con npm audit / pip-audit.) En revisión de código: señala libs sin
mantenimiento o versiones muy atrasadas en manejo de auth/crypto/parsing.

## A07 — Identification and Authentication Failures

(Ver skill `authn-authz-review` para el detalle.) En un barrido general: login sin
rate limit, sesiones que no rotan tras login, cookies sin `HttpOnly`/`Secure`/`SameSite`,
tokens de reset predecibles o sin expiración, ausencia de MFA donde importa.

## A08 — Software and Data Integrity Failures

Qué buscar: deserialización insegura, updates/plugins sin verificar firma, CI que
ejecuta código de dependencias no fijadas.
- **Python:** `pickle.loads`/`yaml.load` sobre datos no confiables → `yaml.safe_load`,
  evitar pickle de fuentes externas.
- **Node:** `eval`, `Function()`, deserializadores inseguros sobre input.

## A09 — Security Logging and Monitoring Failures

Qué buscar: eventos de seguridad (login fallido, cambios de permisos) sin log; o el
opuesto — logging de datos sensibles (passwords, tokens, PII, tarjetas). Equilibra:
registra el evento, nunca el secreto.

## A10 — Server-Side Request Forgery (SSRF)

Qué buscar: el servidor hace fetch a una URL que viene del usuario (webhooks,
previews, importadores de imagen).
- Patrón: `fetch(req.body.url)` / `requests.get(user_url)` sin validar destino.
- Fix: allowlist de dominios, bloquear IPs internas/metadata (169.254.169.254,
  localhost, rangos privados), resolver DNS y validar la IP final, sin seguir redirects ciegamente.

---

## Notas de calibración de severidad

- **Crítica:** ejecución remota, SQLi/command injection explotable, auth bypass, exposición masiva de datos.
- **Alta:** IDOR con datos sensibles, XSS almacenado, SSRF a red interna.
- **Media:** XSS reflejado con precondiciones, CORS laxo, falta de rate limit en login.
- **Baja:** headers faltantes sin impacto directo demostrado, verbosidad de errores.

Siempre baja la severidad si hay mitigaciones aguas arriba (WAF no cuenta como fix del código).
