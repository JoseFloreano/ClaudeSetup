# ══════════════════════════════════════════════════════════════
#  restore-graph.ps1 — Restauración CORRECTA de un backup (Windows)
#
#  Por qué existe (auditoría A3): el compose corre con --appendonly yes.
#  Con AOF activo, el server carga del AOF al arrancar e IGNORA dump.rdb.
#  Copiar el .rdb a mano y reiniciar "termina sin error" y no restaura NADA.
#
#  Procedimiento AOF-safe: detener stack → cuarentena de datos viejos →
#  colocar dump.rdb → recovery con appendonly OFF (carga el RDB) →
#  VERIFICAR DBSIZE > 0 → CONFIG SET appendonly yes (regenera AOF) →
#  levantar stack normal → verificar contra manifiesto.
#
#  Uso:
#    .\restore-graph.ps1                          # último backup
#    .\restore-graph.ps1 -BackupFile "C:\...\graphiti_20260712.rdb"
# ══════════════════════════════════════════════════════════════

param(
    [string]$BackupFile = "",
    [string]$GraphitiLocal = "$env:LOCALAPPDATA\graphiti"
)

$ErrorActionPreference = "Stop"
function Write-OK   { param($m) Write-Host "  [OK] $m"   -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m"  -ForegroundColor Red }

$EnvFile     = Join-Path $GraphitiLocal ".env"
$ComposeFile = Join-Path $GraphitiLocal "docker-compose.yml"
$DataDir     = Join-Path $GraphitiLocal "data"

if (-not (Test-Path $EnvFile)) { Write-Err "No existe $EnvFile. Corre setup-new-machine.ps1 primero."; exit 1 }

function Get-EnvVal { param($k)
    $line = Get-Content $EnvFile | Where-Object { $_ -match "^$k=" } | Select-Object -Last 1
    if ($line) { return ($line -split '=', 2)[1] } else { return "" }
}
$BackupDir       = Get-EnvVal "BACKUP_DIR"
$FalkordbVersion = Get-EnvVal "FALKORDB_VERSION"
$DataPathDocker  = Get-EnvVal "FALKORDB_DATA_PATH"
if (-not $FalkordbVersion) { Write-Err "FALKORDB_VERSION vacío en .env"; exit 1 }
if ($DataPathDocker -match "OneDrive") { Write-Err "FALKORDB_DATA_PATH apunta a OneDrive — prohibido (H2)."; exit 1 }

# ── 1. Elegir backup ──────────────────────────────────────────────────────
if (-not $BackupFile) {
    $latest = Get-ChildItem "$BackupDir\*.rdb" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Write-Err "No hay backups .rdb en $BackupDir"; exit 1 }
    $BackupFile = $latest.FullName
}
if (-not (Test-Path $BackupFile)) { Write-Err "No existe $BackupFile"; exit 1 }

$expectedDbsize = -1
$manifestPath = $BackupFile -replace '\.rdb$', '.manifest.json'
if (Test-Path $manifestPath) {
    try {
        $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $expectedDbsize = $m.dbsize
        Write-Host "  Backup: $(Split-Path $BackupFile -Leaf) | host origen: $($m.hostname) | dbsize esperado: $expectedDbsize"
    } catch { }
}
$go = Read-Host "  ¿Restaurar este backup? Los datos actuales van a cuarentena. [s/N]"
if ($go -notin @('s','S','y','Y')) { Write-Host "Cancelado."; exit 0 }

# ── 2. Detener stack y poner datos actuales en cuarentena ────────────────
docker rm -f graphiti-restore 2>$null | Out-Null
if (Test-Path $ComposeFile) {
    docker compose --env-file $EnvFile -f $ComposeFile stop 2>$null | Out-Null
}
docker stop graphiti-mcp-server graphiti-falkordb 2>$null | Out-Null
Write-OK "Stack detenido"

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$quarantine = Join-Path $DataDir "pre-restore-$ts"
$oldFiles = Get-ChildItem $DataDir -File | Where-Object { $_.Extension -in @('.rdb', '.aof', '.manifest') }
$aofDir = Join-Path $DataDir "appendonlydir"
if ($oldFiles -or (Test-Path $aofDir)) {
    New-Item -ItemType Directory -Force -Path $quarantine | Out-Null
    $oldFiles | ForEach-Object { Move-Item $_.FullName $quarantine }
    if (Test-Path $aofDir) { Move-Item $aofDir $quarantine }
    Write-OK "Datos previos en cuarentena: $quarantine"
}

# ── 3. Colocar el dump.rdb y arrancar recovery SIN AOF ────────────────────
Copy-Item $BackupFile (Join-Path $DataDir "dump.rdb") -Force
docker run -d --name graphiti-restore `
    -v "${DataPathDocker}:/var/lib/falkordb/data" `
    -e "REDIS_ARGS=--appendonly no" `
    "falkordb/falkordb:$FalkordbVersion" | Out-Null
Write-OK "Container de recovery arrancado (appendonly OFF → carga el RDB)"

$pinged = $false
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 1
    $ping = docker exec graphiti-restore redis-cli ping 2>$null
    if ($ping -match "PONG") { $pinged = $true; break }
}
if (-not $pinged) { Write-Err "Recovery no responde. Ver: docker logs graphiti-restore"; exit 1 }

# ── 4. VERIFICAR que los datos cargaron ───────────────────────────────────
$dbsizeRaw = docker exec graphiti-restore redis-cli DBSIZE 2>$null
$dbsize = if ($dbsizeRaw -match '(\d+)') { [int]$Matches[1] } else { 0 }
if ($dbsize -eq 0) {
    Write-Err "RESTAURACIÓN FALLIDA: DBSIZE=0 — el RDB no cargó."
    Write-Err "Datos previos intactos en: $quarantine"
    docker rm -f graphiti-restore 2>$null | Out-Null
    exit 1
}
if ($expectedDbsize -ne -1 -and $dbsize -ne $expectedDbsize) {
    Write-Warn "DBSIZE=$dbsize difiere del manifiesto ($expectedDbsize). Revisa antes de confiar."
} else {
    Write-OK "Datos cargados: DBSIZE=$dbsize"
}

# ── 5. Regenerar el AOF desde los datos cargados ──────────────────────────
docker exec graphiti-restore redis-cli CONFIG SET appendonly yes | Out-Null
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 1
    $info = docker exec graphiti-restore redis-cli INFO persistence 2>$null
    if ($info -match "aof_rewrite_in_progress:0") { break }
}
Write-OK "AOF regenerado desde el snapshot restaurado"

# ── 6. Apagar recovery y levantar el stack normal ─────────────────────────
docker exec graphiti-restore redis-cli BGSAVE 2>$null | Out-Null
Start-Sleep -Seconds 2
docker rm -f graphiti-restore | Out-Null
if (Test-Path $ComposeFile) {
    docker compose --env-file $EnvFile -f $ComposeFile up -d | Out-Null
    Start-Sleep -Seconds 5
    $final = docker exec graphiti-falkordb redis-cli DBSIZE 2>$null
    Write-OK "Stack levantado. DBSIZE final: $final"
} else {
    Write-Warn "No encontré $ComposeFile — levanta el stack manualmente."
}

Write-Host ""
Write-OK "Restauración completada y VERIFICADA. Cuarentena borrable tras confirmar: $quarantine"
