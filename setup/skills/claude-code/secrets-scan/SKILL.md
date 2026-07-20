---
name: secrets-scan
description: >
  Detecta credenciales, API keys, tokens y llaves privadas hardcodeadas en el código
  antes de commitear o publicar, y guía la remediación (rotar + mover a entorno). Use
  when the user says "busca secretos", "hay claves hardcodeadas", "revisa antes de
  commit", "credenciales expuestas", "pre-commit", or before pushing/opening a PR.
---

# Secrets Scan

Encuentra secretos en el código (OWASP A02/A05) antes de que lleguen al historial de
git, donde ya se consideran comprometidos.

## Requisitos

- **Toolchain local** (Claude Code): acceso a git y, si están, a `gitleaks`/`trufflehog`.
- En **Cowork**: analiza los archivos que el usuario conecte/pegue con las heurísticas de
  abajo; el escaneo del historial de git requiere el puente del desktop. Dilo si no aplica.

## Pasos

1. **Delimita el alcance:** cambios *staged* (`git diff --cached`), el working tree, o el
   historial (`git log -p`). Por defecto, lo que está por commitearse.
2. **Escanea.** Si hay herramienta dedicada, úsala (`gitleaks detect`, `trufflehog`).
   Si no, aplica heurísticas por patrón:
   - Llaves de proveedor: AWS `AKIA[0-9A-Z]{16}`, Google `AIza...`, Slack `xox[baprs]-...`,
     Stripe `sk_live_...`, GitHub `ghp_...`.
   - Llaves privadas: `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----`.
   - JWTs y tokens largos; cadenas de **alta entropía** en asignaciones.
   - Nombres reveladores: `api_key=`, `secret=`, `password=`, `token=`, `client_secret=`
     con un literal no vacío a la derecha.
3. **Filtra falsos positivos:** placeholders (`.env.example`, `<your-key>`, `xxxx`),
   fixtures de test claramente ficticios, valores de ejemplo en docs. No infles el reporte.
4. **Por cada secreto real, reporta:** `archivo:línea`, tipo de secreto, y la **remediación
   en orden**:
   a) **Rotar/revocar la credencial** — si estuvo en un commit, ya está comprometida aunque
      la borres; rotar es obligatorio, no opcional.
   b) Mover el valor a variable de entorno / gestor de secretos y leerlo desde ahí.
   c) Añadir el archivo a `.gitignore` (p. ej. `.env`).
   d) Si ya se pusheó, limpiar el historial (`git filter-repo` / BFG) y avisar al equipo.
5. **Verifica:** re-escanea el alcance y confirma que no quedan hallazgos reales.

## Qué NO hacer

- No muestres el secreto completo en el reporte: enmascara (`AKIA…4F2X`) para no re-exponerlo.
- No te limites a borrar la línea: sin rotar, la credencial sigue viva en el historial.
