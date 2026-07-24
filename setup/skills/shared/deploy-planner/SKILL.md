---
name: deploy-planner
description: >
  Planea el despliegue a producción de una app/API entrevistando al usuario
  con el cuestionario de despliegue (plataforma, secrets, DB/migraciones,
  dominio/TLS, CI/CD, rollback, observabilidad, costos) y produce el plan +
  checklist de go-live. Use when the user says "vamos a desplegar",
  "¿qué necesito para producción?", "deploy", "súbelo a producción",
  "production readiness", or when a project approaches its first release.
  NO ejecuta el despliegue — lo planea y deja el runbook.
---

# Deploy Planner

No existe skill mantenida de production-readiness para dev individual (hueco
verificado) — esta es la nuestra. Método: **entrevista → plan → gates → runbook**.
El despliegue perfecto es aburrido: todo estaba decidido antes de tocar nada.

## Pasos

1. **Entrevista con el cuestionario** (`references/deploy-questionnaire.md`):
   hazlo conversacional, por bloques, saltando lo que ya se sepa por el
   contexto del proyecto. NO preguntes las 8 secciones de golpe — 2-3 bloques
   por turno, propón defaults sensatos del propio cuestionario y deja que el
   usuario corrija. Anota las respuestas.
2. **Detecta los rojos**: respuestas tipo "no sé" en secrets, backups,
   rollback o costos son bloqueantes de go-live — márcalos como decisiones
   pendientes, no los rellenes con suposiciones.
3. **Produce el plan de despliegue** en
   `10-Projects/<proyecto>/deploy-plan.md` (vault): plataforma elegida y por
   qué, mapa de secrets, estrategia de DB/migraciones, pipeline, plan de
   rollback probado, observabilidad mínima, presupuesto mensual estimado.
4. **Gates de go-live** (del cuestionario §8): nada se despliega con un gate
   en rojo. El plan lista cada gate con su estado.
5. **Primera vez en la plataforma elegida**: valida contra la doc oficial del
   día (WebSearch) — los free tiers y precios cambian; no confíes en memoria.
6. **Registra**: la elección de plataforma y las decisiones de arquitectura
   de deploy → `adr-writer`. Costos estimados vs reales al mes → pendiente en
   el vault para revisar.

## División Code/Cowork

- Planear (esta skill): ambos.
- Ejecutar el deploy (CLI de plataforma, secrets reales, DNS): **Claude Code**
  en la laptop — nunca pongas secrets reales en el plan del vault (nombres de
  variables sí, valores jamás).

## Referencias

- `references/deploy-questionnaire.md` — el cuestionario completo de 8
  secciones con defaults para el stack (Next.js/FastAPI/Flutter) y gates.
