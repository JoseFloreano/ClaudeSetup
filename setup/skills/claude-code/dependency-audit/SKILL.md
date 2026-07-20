---
name: dependency-audit
description: >
  Escanea las dependencias del proyecto en busca de CVEs conocidos (npm audit,
  pip-audit, etc.), prioriza por severidad y propone los upgrades mínimos seguros.
  Use when the user says "revisa las dependencias", "hay vulnerabilidades en las
  librerías", "corre npm audit", "dependencias desactualizadas", "SCA", or before a
  release/deploy. Cubre ecosistemas JS (npm/yarn/pnpm) y Python (pip/poetry/pipenv).
---

# Dependency Audit

Detecta componentes vulnerables (OWASP A06) corriendo el escáner nativo del
ecosistema y traduciendo el resultado a un plan de acción priorizado.

## Requisitos

- **Toolchain local** (Claude Code): necesita el gestor de paquetes instalado.
- En **Cowork** (sandbox cloud) esto no corre directo: pide correrlo vía el puente
  del desktop app, o que el usuario pegue el `package-lock.json` / `requirements.txt`
  y analiza offline lo que se pueda. Dilo, no falles en silencio.

## Pasos

1. **Detecta el ecosistema** por los lockfiles presentes: `package-lock.json` /
   `yarn.lock` / `pnpm-lock.yaml` (JS) o `requirements.txt` / `poetry.lock` /
   `Pipfile.lock` (Python). Si hay varios, córrelos todos.
2. **Corre el escáner** correspondiente y captura la salida en JSON cuando se pueda:
   - npm: `npm audit --json`   · yarn: `yarn npm audit --json`   · pnpm: `pnpm audit --json`
   - Python: `pip-audit -r requirements.txt` o `pip-audit` (entorno activo); poetry: `pip-audit`.
   Si la herramienta no está, instálala o indícalo (`pip install pip-audit`).
3. **Prioriza** los hallazgos por: severidad (crítica/alta primero), si el paquete es
   dependencia directa o transitiva, si hay **fix disponible**, y si la ruta vulnerable
   es realmente usada por el proyecto (reachability, cuando puedas inferirlo).
4. **Propón el arreglo mínimo:** la versión objetivo más baja que cierra el CVE. Marca
   si es patch/minor (seguro) o **major con posible breaking change** (avisa y no lo
   apliques a ciegas). Usa `npm audit fix` / bump manual según el caso.
5. **Aplica solo lo aprobado** y **re-corre el escáner** para confirmar que el conteo
   bajó. Nunca cierres el audit sin verificar.
6. **Entrega:** tabla corta por severidad (paquete, versión actual → objetivo, CVE,
   directa/transitiva, breaking sí/no) + los comandos exactos para aplicar.

## Notas

- Un CVE sin fix disponible: documenta el mitigante (config, WAF, feature flag) y déjalo
  registrado; no lo ignores.
- No subas versiones mayores "de paso" sin CVE que lo justifique — sale del alcance.
- Complementa a `web-security-review` (A06); esta skill es la parte automatizada.
