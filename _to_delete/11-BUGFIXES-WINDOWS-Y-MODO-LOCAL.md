# Bugfixes: Windows PowerShell 5.1 y modo single-laptop

> Hallazgos de la primera instalación real del setup en una laptop **sin OneDrive**
> (modo single-laptop, Graphiti descartado). Fecha: 2026-07-14.
>
> Los 5 bugs de abajo eran **bloqueantes**: con el repo tal como estaba, ninguno de
> los scripts `.ps1` corría y el plugin de Cowork no cargaba. Cuatro de los cinco
> afectan también a la laptop con OneDrive — no son específicos del modo local.

---

## Resumen

| # | Bug | Archivos | ¿Afecta a la laptop con OneDrive? |
|---|-----|----------|-----------------------------------|
| B1 | Los `.ps1` no parsean en Windows PowerShell (UTF-8 sin BOM) | los 4 `.ps1` de `setup/` | **Sí** (si usa `powershell.exe`; no si usa `pwsh` 7) |
| B2 | `if` como expresión con `elseif` en línea nueva | `sync-skills.ps1` | **Sí** |
| B3 | El zip de Cowork usa `\` como separador de rutas | `sync-skills.ps1` | **Sí** |
| B4 | `plugin.json` con BOM → el validador de plugins lo rechaza | `sync-skills.ps1` | **Sí** |
| B5 | Las skills hardcodean el vault a OneDrive y abortan sin él | 3 × `SKILL.md` | No (pero el fix es compatible) |

---

## B1 — Los `.ps1` no parsean en Windows PowerShell 5.1

**Síntoma.** Cualquier script de `setup/` falla antes de ejecutar una sola línea:

```
Falta la llave de cierre "}" en el bloque de instrucciones o la definición de tipo.
```

El error apunta a llaves que **sí** están correctamente balanceadas. Es un error fantasma.

**Causa raíz.** Los archivos están guardados en **UTF-8 sin BOM**. Windows PowerShell 5.1
(`powershell.exe`) asume la codepage ANSI (cp1252) cuando un `.ps1` no lleva BOM.

Los caracteres de caja que decoran los comentarios (`─` = `E2 94 80`, `—` = `E2 80 94`)
contienen el byte **`0x94`**, que en cp1252 es la comilla tipográfica de cierre `"`.
**PowerShell trata las comillas tipográficas como delimitadores de string reales.**

Resultado: cada `─` inyecta una comilla suelta. Con un número impar, se abre un string
que se traga el resto del archivo — y el parser reporta las llaves de ese texto tragado
como "faltantes".

**Por qué nunca se notó:** PowerShell 7 (`pwsh`) asume UTF-8 por defecto, con o sin BOM.
El bug solo aparece en `powershell.exe`, que es lo que usa Task Scheduler y lo que
invocan las instrucciones del README (`Register-ScheduledTask -Execute "powershell.exe"`).
Es decir: **las tareas programadas de backup nunca habrían corrido.**

**Fix.** Reguardar los 4 `.ps1` como **UTF-8 con BOM**. El contenido no cambia.

```powershell
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
Get-ChildItem setup -Filter *.ps1 | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName, [System.Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($_.FullName, $text, $utf8Bom)
}
```

**Verificación** (0 errores en los 4):

```powershell
$errs = $null
[System.Management.Automation.PSParser]::Tokenize((Get-Content $f -Raw), [ref]$errs)
$errs.Count   # -> 0
```

> **Regla para el futuro:** todo `.ps1` de este repo que contenga cualquier carácter
> no-ASCII (acentos incluidos) **debe** llevar BOM. Es la única forma de que
> `powershell.exe` lo lea bien.

---

## B2 — `if` como expresión con `elseif` en línea nueva

**Síntoma.** Mismo error de llaves que B1, y persiste incluso tras arreglar la codificación.

**Causa raíz.** `sync-skills.ps1` resolvía la raíz de OneDrive así:

```powershell
$od = if ($env:OneDrive -and (Test-Path $env:OneDrive)) { $env:OneDrive }
      elseif (Test-Path "$env:USERPROFILE\OneDrive") { "$env:USERPROFILE\OneDrive" }
      else { $null }
```

PowerShell permite `}` ⏎ `elseif` cuando el `if` es una **sentencia**, pero **no** cuando
se usa como **expresión** asignada a una variable. Ahí el salto de línea cierra la
expresión y el `elseif` queda huérfano.

**Fix.** Reescribir en forma de sentencia:

```powershell
$od = $null
if ($env:OneDrive -and (Test-Path $env:OneDrive)) { $od = $env:OneDrive }
elseif (Test-Path "$env:USERPROFILE\OneDrive") { $od = "$env:USERPROFILE\OneDrive" }
if (-not $od) {
    $od = $env:USERPROFILE   # modo single-laptop
    ...
}
```

---

## B3 — El zip del plugin de Cowork usa `\` como separador

**Síntoma.** Al subir `dev-skills.zip` en Cowork → Customize → Plugins:

```
Error al cargar el plugin — archivos con caracteres inválidos
```

**Causa raíz.** `Compress-Archive` en Windows PowerShell 5.1 escribe los nombres de
entrada con el separador del **sistema operativo** (`\`):

```
dev-skills\skills\adr-writer\SKILL.md      ← inválido
```

El spec de ZIP (APPNOTE 4.4.17) exige **`/`** como separador, siempre. El Explorador de
Windows abre esos zips igual, así que el defecto pasa desapercibido — pero un cargador
estricto ve el `\` como parte del *nombre* del archivo y lo rechaza por carácter inválido.

Corregido en PowerShell 7 / .NET Core; sigue roto en PS 5.1.

**Fix.** No usar `Compress-Archive`. Construir el zip a mano normalizando las rutas:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    Get-ChildItem $pluginDir -Recurse -File | ForEach-Object {
        $rel   = $_.FullName.Substring($pluginDir.Length).TrimStart([char]92)
        $entry = $zip.CreateEntry(($rel -replace '\\', '/'), 'Optimal')   # <- '/'
        $out   = $entry.Open()
        $bytes = [IO.File]::ReadAllBytes($_.FullName)
        $out.Write($bytes, 0, $bytes.Length)
        $out.Dispose()
    }
} finally { $zip.Dispose() }
```

**Verificación:**

```powershell
$z = [IO.Compression.ZipFile]::OpenRead($zipPath)
$z.Entries | ForEach-Object { $_.FullName }   # todas con '/'
$z.Dispose()
```

---

## B4 — `plugin.json` con BOM: el validador de plugins lo rechaza

**Síntoma.** Tras arreglar B3, el zip carga pero falla la validación:

```
Plugin failed validation with 1 error.
Invalid JSON in plugin.json: Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)
```

**Causa raíz.** `Out-File -Encoding UTF8` en PowerShell 5.1 escribe **UTF-8 con BOM**
(no hay forma de desactivarlo con ese cmdlet; PS 7 sí distingue `utf8` de `utf8BOM`).
El estándar JSON (RFC 8259 §8.1) **prohíbe** el BOM, y el validador de plugins lo rechaza.

> **Nota:** es el problema **inverso** a B1. Los `.ps1` *necesitan* BOM para que
> `powershell.exe` los lea; el `.json` *no debe* tenerlo. No generalizar en una sola
> dirección: **depende de quién consume el archivo.**

**Fix.** Escribir el manifiesto sin BOM:

```powershell
$manifest = @{ name = "dev-skills"; description = "..."; version = (Get-Date -Format 'yyyy.MM.dd') } | ConvertTo-Json
[IO.File]::WriteAllText($path, $manifest, (New-Object System.Text.UTF8Encoding($false)))
```

**Verificación:**

```powershell
$b = [IO.File]::ReadAllBytes($path)
$b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF   # -> False
```

### Estructura del zip que Cowork acepta

La subida por zip **no está documentada** (ni en el artículo de soporte de plugins ni en
la referencia de plugins de Claude Code). Verificado empíricamente: el plugin root va en
la **raíz del zip**, sin carpeta envolvente.

```
dev-skills.zip
├── .claude-plugin/plugin.json      ← en la raíz, sin BOM, rutas con '/'
└── skills/
    ├── adr-writer/SKILL.md
    ├── memory-keeper/SKILL.md
    └── project-resume/SKILL.md
```

**Ruta de instalación:** Cowork → **Customize → Plugins → Browse plugins → subir el
plugin personalizado**. Arrastrar el `.zip` a un chat **no lo instala** — solo lo adjunta
como archivo a esa conversación.

---

## B5 — Las skills hardcodean el vault a OneDrive

**Síntoma.** En modo single-laptop, `project-onboard` se niega a funcionar: su sección
Requisitos decía literalmente *"Vault en `OneDrive/DevSetup/ObsidianVault/`. Si no existe,
**PARA** y avisa"*. Sin OneDrive, la skill aborta aunque el vault exista en el home.

**Causa raíz.** El `setup/README.md` documenta el modo single-laptop (raíz `DevSetup/` en
el home), pero las skills nunca se actualizaron para contemplarlo. Los scripts sí caen
solos a modo local; las skills no.

**Fix.** Hacer las 3 skills agnósticas de la raíz — aceptan OneDrive **o** home, de modo
que el mismo `SKILL.md` sirve en ambas laptops:

- `setup/skills/claude-code/project-onboard/SKILL.md`
- `setup/skills/claude-code/project-resume/SKILL.md`
- `setup/skills/shared/adr-writer/SKILL.md`

```markdown
- Vault en `DevSetup/ObsidianVault/`, bajo OneDrive (multi-laptop) o bajo el home /
  `%USERPROFILE%` (single-laptop) — usa la raíz que exista.
```

---

## Estado final en la laptop single-laptop

Lo que quedó instalado, para referencia al replicar:

```
~/.local/bin/            claude, uv, graphify        (PATH de usuario)
~/.claude/
  ├── CLAUDE.md          ~200 tokens (bajo el límite de H4); sin Graphiti
  ├── settings.json      env.ENABLE_TOOL_SEARCH = "1"   (H3)
  └── skills/            adr-writer, memory-keeper, project-onboard,
                         project-resume, graphify
~/DevSetup/
  ├── claude-skills/     fuente de verdad: {shared, claude-code, cowork}
  │   └── _build/dev-skills.zip     → subir a Cowork
  └── ObsidianVault/     git → github.com/joselfloreano/obsidian-vault (privado)

MCPs (scope user):  context7, obsidian-vault (filesystem → el vault)
Plugins:            superpowers 6.1.1
Cowork:             plugin dev-skills (adr-writer, memory-keeper, project-resume)
```

**Descartado a propósito:** Graphiti + FalkorDB + Docker (ya estaba pospuesto en
`setup/README.md`) y OneDrive. El vault de Obsidian es la única memoria durable.

### La deuda del modo local

Los backups del grafo no aplican (no hay grafo), pero **el vault vive en un solo disco**.
Su remote de GitHub deja de ser opcional y pasa a ser la única copia fuera de la máquina:
configurar **Obsidian Git** (auto pull/push cada 10 min) no es cosmético — es el backup.

---

## Post-verificación (Cowork, 2026-07-22)

Comprobación independiente del reporte contra el estado real del repo:

**El diagnóstico de los 5 bugs es correcto** (B1–B3 confirmados directamente en el
código; B4/B5 consistentes). Pero se encontraron dos problemas al verificar:

1. **Los fixes B1–B5 NO estaban en el repo** — vivían solo en las copias de la
   laptop single-laptop. Los 4 `.ps1` seguían sin BOM, `sync-skills.ps1` conservaba
   el `if`-expresión roto y `Compress-Archive`, y las 3 skills seguían hardcodeando
   OneDrive.
2. **Regresión adicional no reportada:** `setup-new-machine.ps1` y
   `setup-new-machine.sh` estaban revertidos a la versión **pre-auditoría**
   (sin fixes A1–A4 del doc 09, sin modo `-Local`/`LOCAL=1`) — presumiblemente por
   un merge/pull que pisó las versiones corregidas con una base vieja.
   `project-onboard` también había perdido el fallback del template.

**Reparado en el repo (2026-07-22):** ambos bootstrap reconstruidos (auditoría doc 09
+ modo single-laptop + rutas de provider gemini/groq), B1 aplicado (BOM en los 4
`.ps1`), B2/B3/B4 aplicados a `sync-skills.ps1`, B5 aplicado a las 3 skills, y
además el **equivalente de B3 en `sync-skills.sh`**: hacía el zip con carpeta
envolvente `dev-skills/` — con la estructura verificada (plugin root en la raíz
del zip), ese zip también habría sido rechazado en macOS/Linux.

**Regla de flujo git para que no se repita:** los archivos que Cowork/Claude Code
escriben en el disco NO están en git hasta que se commitean. Antes de trabajar el
repo desde otra laptop: `git add + commit + push` en la laptop actual, y `git pull`
en la otra ANTES de editar. Si un pull toca `setup/`, re-verificar que
`setup-new-machine.ps1` conserva el modo `-Local` (grep rápido: `GraphitiLocal`).
