---
name: nombre-en-kebab-case
description: >
  [QUÉ hace la skill en una frase] + [CUÁNDO debe activarse: "Use when the user..."]
  + [PALABRAS GATILLO literales que el usuario diría, entre comillas]. Escríbela en
  el mismo idioma en que sueles pedir las cosas. Esta descripción es lo ÚNICO que el
  agente ve antes de decidir usar la skill — es el trigger, no documentación.
---

# Nombre de la Skill

<!--
REGLAS PARA QUE SE USE AUTOMÁTICAMENTE (borrar este bloque al crear la skill):

1. La description debe responder: ¿qué hace? ¿cuándo? ¿con qué frases se pide?
   MAL:  "Skill para ADRs."
   BIEN: "Documenta decisiones de arquitectura como ADR en el vault. Use when the
          user decides between technologies, says 'decidimos usar X', 'por qué
          elegimos', 'ADR', or resolves a design trade-off."

2. Cuerpo < 500 palabras. Lo extenso va en archivos junto a este SKILL.md
   (references/*.md, scripts/*) y se referencia desde aquí — el agente solo los
   abre si los necesita.

3. Si la skill depende de algo (MCP, herramienta, carpeta), decláralo en
   "Requisitos" con el fallback: qué hacer si no está disponible. Así la misma
   skill sirve en Claude Code y en Cowork.

4. Instrucciones imperativas y numeradas. Nada de teoría.
-->

## Cuándo usar

- [Situación concreta 1]
- [Situación concreta 2]

## Requisitos

- [Herramienta/MCP/carpeta necesaria] — si no está disponible: [fallback].

## Pasos

1. [Paso imperativo]
2. [Paso imperativo]
3. Verifica el resultado antes de dar por terminado: [criterio de éxito].

## Referencias

- [references/detalle.md — solo si hace falta material extenso]
