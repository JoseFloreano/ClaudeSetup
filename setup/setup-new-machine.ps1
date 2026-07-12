# ══════════════════════════════════════════════════════════════
#  setup-new-machine.ps1 — Bootstrap Graphiti en Windows
#  Ejecutar en PowerShell como administrador:
#    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#    .\setup-new-machine.ps1
#    .\setup-new-machine.ps1 -OneDrivePath "D:\OneDrive"
# ══════════════════════════════════════════════════════════════

param(
    [string]$OneDrivePath = "$env:USERPROFILE\OneDrive",
    [switch]$SkipRestore = $false
)

$ErrorActionPreference = "Stop"
$DevSetup       = "$OneDrivePath\DevSetup"
$GraphitiData   = "$DevSetup\graphiti-data"
$GraphitiDocker = "$DevSetup\graphiti-docker"

function Write-Header { param($msg) Write-Host "`n▶ $msg" -ForegroundColor Blue -NoNewline; Write-Host "" }
function Write-OK     { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err    { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor Cyan }

Write-Host "`n════════════════════════════════════════════════════" -ForegroundColor White
Write-Host " Graphiti + FalkorDB — Setup Windows" -ForegroundColor White
Write-Host " OneDrive: $OneDrivePath" -ForegroundColor White
Write-Host "════════════════════════════════════════════════════`n" -ForegroundColor White

# ── 1. Verificar dependencias ──────────────────────────────────────────────
Write-Header "Verificando dependencias"
$errors = 0

try { docker --version | Out-Null; Write-OK "Docker instalado" }
catch { Write-Err "Docker no encontrado. Instala Docker Desktop."; $errors++ }

try { docker compose version | Out-Null; Write-OK "Docker Compose disponible" }
catch { Write-Err "Docker Compose no disponible."; $errors++ }

if (-not (Test-Path $DevSetup)) {
    Write-Warn "No se encontró $DevSetup. Creando..."
    New-Item -ItemType Directory -Force -Path $DevSetup | Out-Null
}

if ($errors -gt 0) { Write-Err "Corrige $errors errores críticos antes de continuar."; exit 1 }

# ── 2. Crear directorios ───────────────────────────────────────────────────
Write-Header "Creando directorios"
@("$GraphitiData\falkordb", "$GraphitiData\backups", "$GraphitiData\config", $GraphitiDocker) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}
Write-OK "Directorios creados en $GraphitiData"

# ── 3. Copiar config desde dotfiles ───────────────────────────────────────
Write-Header "Configurando archivos"
$dotfiles = "$DevSetup\claude-dotfiles\graphiti"
if (Test-Path "$dotfiles\docker-compose.yml") {
    Copy-Item "$dotfiles\docker-compose.yml" "$GraphitiDocker\" -Force
    Write-OK "docker-compose.yml copiado"
} else { Write-Warn "docker-compose.yml no encontrado en dotfiles. Copia manualmente." }

if (Test-Path "$dotfiles\config.yaml") {
    Copy-Item "$dotfiles\config.yaml" "$GraphitiData\config\" -Force
    Write-OK "config.yaml copiado"
}

# ── 4. Crear .env ─────────────────────────────────────────────────────────
Write-Header "Creando .env"
$envFile = "$GraphitiDocker\.env"
if (-not (Test-Path $envFile)) {
    @"
# Auto-generado por setup-new-machine.ps1 en $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')
FALKORDB_DATA_PATH=$GraphitiData\falkordb
CONFIG_PATH=$GraphitiData\config

LLM_PROVIDER=openai
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

MODEL_NAME=gpt-4.1-mini
SMALL_MODEL_NAME=gpt-4.1-nano

FALKORDB_PASSWORD=
SEMAPHORE_LIMIT=3
"@ | Out-File -FilePath $envFile -Encoding UTF8
    Write-OK ".env creado"
    Write-Warn "IMPORTANTE: Edita $envFile con tus API keys."
    $edit = Read-Host "  ¿Abrir .env en Notepad ahora? [s/N]"
    if ($edit -eq 's' -or $edit -eq 'S') { notepad $envFile; Start-Sleep -Seconds 2 }
} else { Write-OK ".env ya existe" }

# ── 5. Agregar Graphiti al MCP de Claude Code ────────────────────────────
Write-Header "Configurando MCP"
try {
    $mcpList = claude mcp list 2>&1
    if ($mcpList -match "graphiti") {
        Write-OK "MCP 'graphiti-memory' ya configurado"
    } else {
        claude mcp add --transport http graphiti-memory "http://localhost:8000/mcp/" -s user
        Write-OK "MCP graphiti-memory agregado"
    }
} catch { Write-Warn "No se pudo configurar MCP automáticamente. Ejecuta manualmente:" ; Write-Info "claude mcp add --transport http graphiti-memory http://localhost:8000/mcp/ -s user" }

# ── 6. Restaurar backup ───────────────────────────────────────────────────
Write-Header "Verificando backups"
$latestBackup = Get-ChildItem "$GraphitiData\backups\*.rdb" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latestBackup -and -not $SkipRestore) {
    Write-Info "Backup encontrado: $($latestBackup.Name) ($($latestBackup.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
    $restore = Read-Host "  ¿Restaurar este backup? [s/N]"
    if ($restore -eq 's' -or $restore -eq 'S') {
        Copy-Item $latestBackup.FullName "$GraphitiData\falkordb\dump.rdb" -Force
        Write-OK "Backup restaurado. FalkorDB cargará el grafo al arrancar."
    }
} else { Write-Info "Sin backups previos. Iniciando con grafo vacío." }

# ── 7. Levantar containers ────────────────────────────────────────────────
Write-Header "Levantando Docker"

# IMPORTANTE: Docker en Windows usa paths UNIX para bind mounts.
# Convertimos la ruta de OneDrive al formato que Docker Desktop entiende.
# Ej: C:\Users\foo\OneDrive\... → /c/Users/foo/OneDrive/...
$falkordbPath = ($GraphitiData.Replace('\', '/').Replace('C:', '/c').Replace('D:', '/d'))
Write-Info "Usando FALKORDB_DATA_PATH: $falkordbPath/falkordb"

# Sobreescribir FALKORDB_DATA_PATH en .env con formato UNIX para Docker
(Get-Content $envFile) -replace "^FALKORDB_DATA_PATH=.*", "FALKORDB_DATA_PATH=$falkordbPath/falkordb" |
    Set-Content $envFile
(Get-Content $envFile) -replace "^CONFIG_PATH=.*", "CONFIG_PATH=$falkordbPath/config" |
    Set-Content $envFile

Push-Location $GraphitiDocker
try {
    docker compose up -d
    Write-OK "Containers levantados"
} catch { Write-Err "Error al levantar containers. Verifica Docker Desktop."; exit 1 }
finally { Pop-Location }

# ── 8. Health check ───────────────────────────────────────────────────────
Write-Header "Verificando health (espera 10s...)"
Start-Sleep -Seconds 10

try {
    $ping = docker exec graphiti-falkordb redis-cli ping 2>&1
    if ($ping -match "PONG") { Write-OK "FalkorDB respondiendo" }
    else { Write-Warn "FalkorDB no responde. Verifica: docker logs graphiti-falkordb" }
} catch { Write-Warn "No se pudo verificar FalkorDB." }

# ── 9. Task Scheduler para backup automático ─────────────────────────────
Write-Header "Configurando backup automático (Task Scheduler)"
$backupScript = "$GraphitiDocker\backup-graph.ps1"
if (Test-Path $backupScript) {
    $taskName = "GraphitiBackup"
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NonInteractive -File `"$backupScript`" -OneDrivePath `"$OneDrivePath`""
        $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 4) -Once -At (Get-Date)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Description "Backup del grafo Graphiti a OneDrive" -RunLevel Highest | Out-Null
        Write-OK "Task Scheduler configurado: backup cada 4 horas"
    } else { Write-OK "Task Scheduler ya configurado" }
}

# ── Resumen ───────────────────────────────────────────────────────────────
Write-Host "`n════════════════════════════════════════════════════" -ForegroundColor White
Write-Host " Setup completado" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════`n" -ForegroundColor White
Write-Info "FalkorDB Browser UI : http://localhost:3000"
Write-Info "MCP endpoint        : http://localhost:8000/mcp/"
Write-Info "Datos               : $GraphitiData\falkordb\"
Write-Info "Backups             : $GraphitiData\backups\"
Write-Host ""
Write-Info "Próximos pasos:"
Write-Info "1. Edita $envFile con tus API keys si no lo hiciste"
Write-Info "2. Reinicia MCP: cd $GraphitiDocker; docker compose restart graphiti-mcp"
Write-Info "3. En Claude Code: claude mcp list (para verificar)"
Write-Info "4. Copia .graphiti.json a cada proyecto"
