# Auth Review — Checklist detallado (sesiones, JWT, acceso, flujos)

Referencia de `authn-authz-review`. Patrón vulnerable → fix, por stack.

---

## 1. Control de acceso (OWASP A01)

**IDOR / ownership no verificado** — el hallazgo más común y más grave.

- **Node/Express:**
  ```js
  // MAL: carga por id sin comprobar dueño
  app.get('/api/invoices/:id', auth, async (req,res)=>{
    res.json(await Invoice.findById(req.params.id));
  });
  // BIEN: ata el recurso al usuario autenticado
  const inv = await Invoice.findOne({ _id: req.params.id, userId: req.user.id });
  if (!inv) return res.sendStatus(404);
  ```
- **Django:** `get_object_or_404(Invoice, pk=pk, user=request.user)` en vez de `.get(pk=pk)`.
- **FastAPI/Flask:** filtra por `owner_id == current_user.id` en la query, no después.

**Autorización en el cliente** — ocultar UI no protege el endpoint. Todo route
handler / API route debe re-verificar rol y ownership en el servidor.

**Deny-by-default** — rutas nuevas deben requerir auth explícitamente. Revisa que el
middleware/guard cubra *todas* las rutas sensibles (incluidas admin, export, webhooks).

**Escalada horizontal/vertical** — ¿un rol `user` puede llamar acciones de `admin`
por una ruta sin check de rol? Verifica el check por acción, no solo por login.

## 2. Sesiones y cookies

- Flags obligatorias: `HttpOnly` (no accesible a JS → mitiga XSS), `Secure` (solo HTTPS),
  `SameSite=Lax|Strict` (mitiga CSRF).
  - Express: `cookie: { httpOnly:true, secure:true, sameSite:'lax' }`.
  - Django: `SESSION_COOKIE_HTTPONLY`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE = True`.
- **Rotar** el id de sesión tras login (previene session fixation).
- **Invalidar** en logout server-side (no solo borrar la cookie).
- Expiración razonable + expiración por inactividad para sesiones sensibles.
- **CSRF:** en apps con sesión por cookie, endpoints que mutan estado necesitan token
  anti-CSRF (o `SameSite` estricto + verificación de origen). APIs con Bearer token en
  header no lo necesitan igual, pero verifica que no acepten también la cookie.

## 3. JWT

- Rechazar `alg: none`; fijar el algoritmo esperado al verificar (no confiar en el header).
- Validar firma **y** claims: `exp` (expiración), `aud`, `iss`. Sin `exp` = token eterno.
- Secreto/clave fuerte desde entorno; nunca hardcodeado (ver `secrets-scan`).
- El payload es **legible** (base64, no cifrado): nada de datos sensibles dentro.
- Revocación: los JWT no se invalidan solos; para logout real usa lista de revocación,
  tokens de vida corta + refresh, o versión de token por usuario.
- Guardado en cliente: cookie `HttpOnly` es preferible a `localStorage` (evita robo por XSS).

## 4. Contraseñas y credenciales

- Hash con **bcrypt / argon2 / scrypt** (con salt, lento a propósito). Nunca MD5/SHA1/SHA256
  crudo ni texto plano.
- **Rate limiting** en login y en verificación de OTP (previene fuerza bruta / credential stuffing).
- Mensajes de error genéricos ("credenciales inválidas") — no revelar si el usuario existe.
- **Reset de contraseña:** token aleatorio (CSPRNG), de un solo uso, con expiración corta;
  invalidar tras usarlo; no exponer el token en logs ni en la URL de referrers.

## 5. MFA y flujos sensibles

- MFA disponible/forzada donde el riesgo lo amerite (admin, pagos).
- Cambio de email/contraseña: re-autenticar o confirmar por segundo canal.
- Enumeración: registro, login y reset deben responder de forma que no revelen qué
  cuentas existen (mismo mensaje y tiempo similar).

---

## Calibración de severidad (auth)

- **Crítica:** auth bypass, IDOR sobre datos sensibles a escala, `alg:none` aceptado,
  contraseñas en texto plano.
- **Alta:** escalada de privilegios, session fixation, reset token predecible, sin rate limit.
- **Media:** cookies sin `SameSite`, falta de rotación de sesión, enumeración de usuarios.
- **Baja:** expiración de sesión larga sin datos sensibles, mensajes de error algo verbosos.
