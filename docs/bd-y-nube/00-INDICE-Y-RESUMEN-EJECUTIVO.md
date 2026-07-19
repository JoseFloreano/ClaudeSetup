# Investigación Técnica: Skills de Bases de Datos, Big Data y Nube para Claude
## Índice General y Resumen Ejecutivo — Subserie `bd-y-nube`

> **Fecha de investigación:** Julio 2026
> **Alcance:** Estrategias de uso de Claude (Code + Cowork) con skills orientadas a bases de datos, big data y nube, integradas al sistema de skills existente (`setup/skills/`, carpetas `shared/ claude-code/ cowork/`).
> **Relación con la serie principal:** Esta subserie extiende los docs 00–09. Asume como vigentes los hallazgos H1–H10, los anti-patrones del doc 06 y las reglas del sistema de skills (`setup/skills/README.md` y `_template/SKILL.md`).

---

## Índice de Documentos

| # | Documento | Tema central |
|---|-----------|--------------|
| 01 | [Estrategias de Uso con Claude](./01-ESTRATEGIAS-DE-USO-CON-CLAUDE.md) | Las 5 estrategias que estructuran toda la subserie |
---

## Resumen Ejecutivo

### El problema que resuelve esta investigación

El sistema de skills del repo ya funciona (carpeta única en OneDrive, sync a Claude Code, plugin para Cowork), pero está vacío de contenido de dominio. Para trabajo con bases de datos, big data y nube, Claude sin skills se comporta como un ingeniero que conoce toda la sintaxis pero ninguna convención: genera SQL genérico que ignora el dialecto y el naming del proyecto, propone migraciones sin evaluar locks ni rollbacks, escribe Terraform que aplica hoy y se vuelve inmantenible en seis meses, y repite en cada sesión los mismos errores que ya se le corrigieron.

La investigación externa converge en el mismo diagnóstico que la serie principal ya estableció para memoria: **el conocimiento de dominio debe empaquetarse como skills con progressive disclosure, no como prompts repetidos ni como CLAUDE.md enciclopédico.**

### Las tres capas del dominio

```
Capa 1: BASES DE DATOS
"Crea una migración para añadir esta columna"
→ Sin skill: ALTER TABLE genérico, sin evaluar locks ni rollback
→ Con skill: revisión de riesgo (locking, pérdida de datos, índices) antes del DDL

Capa 2: BIG DATA / PIPELINES
"Crea el staging model de la fuente Stripe"
→ Sin skill: modelo dbt que compila pero ignora capas, tests y docs del proyecto
→ Con skill + MCP: modelo validado en vivo contra la DB, con schema YAML y tests

Capa 3: NUBE / IaC
"Levanta la infraestructura para este servicio"
→ Sin skill: Terraform monolítico, sin tagging, sin plan-review
→ Con skill: módulos, plan revisado antes de apply, estándares del proveedor
```

*Siguiente: [Estrategias de Uso con Claude](./01-ESTRATEGIAS-DE-USO-CON-CLAUDE.md)*