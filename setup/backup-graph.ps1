# ══════════════════════════════════════════════════════════════
#  backup-graph.ps1 — Snapshot RDB de FalkorDB → OneDrive (Windows)
#
#  Creado por auditoría A2: la versión Windows NO existía y el Task
#  Scheduler apuntaba a un archivo fantasma → cero backups automáticos.
#
#  Task Scheduler (lo registra setup-new-machine.ps1): cada 4 horas.
#  Ejecutar también SIEMPRE antes de cambiar de laptop.
#
#  Restore: SOLO con restore-graph.ps1 (A3: con AOF activo, copiar
#  dump.rdb a mano NO restaura — el server carga del AOF y lo ignora).
#
#  Uso:
#    .\backup-graph.ps1
#    .\backup-graph.ps1 -OneDrivePath "D:\OneDrive"
# ══════════════════════════════════════════════════════════════

param(
    [string]$OneDrivePath = $(if ($env:OneDrive) { $env:OneDrive } else { "$env:USERPROFILE\OneDrive" }),
    [string]$ContainerName = "graphiti-falkordb",
    [int]$MaxBackups = 15
)

$ErrorActionPreference = "Stop"
# Sin OneDrive → backups en ~\DevSetup (modo single-laptop; mismo layout)
if (-not (Test-Path $OneDrivePath)) { $OneDrivePath = $env:USERPROFILE }
$BackupDir = Join-Path $OneDrivePath "DevSetup\graphiti-data\backups"
$Hostname  = $env:COMPUTERNAME

# ── 1. Verificar container ────────────────────────────────────────────────
$running = docker ps --format '{{.Names}}' 2>$null
if (-not ($running -contains $ContainerName)) {
    Write-Host "[WARN] Container '$ContainerName' no está corriendo. Backup omitido."
    exit 0
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ── 2. Aviso de fork multi-laptop (R1) ───────────────────────────────────
$latestManifest = Get-ChildItem "$BackupDir\*.manifest.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestManifest) {
    try {
        $lastHost = (Get-Content $latestManifest.FullName -Raw | ConvertFrom-Json).hostname
        if ($lastHost -and $lastHost -ne $Hostname) {
            Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
            Write-Host "[⚠ FORK WARNING] El backup más reciente lo escribió '$lastHost'." -ForegroundColor Yellow
            Write-Host "  Si NO restauraste desde él en esta máquina (restore-graph.ps1)," -ForegroundColor Yellow
            Write-Host "  este backup guardará una historia DIVERGENTE del grafo." -ForegroundColor Yellow
            Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
        }
    } catch { }
}

# ── 3. Trigger BGSAVE y esperar a que termine ─────────────────────────────
Write-Host "[INFO] Triggering BGSAVE en FalkorDB..."
$beforeSave = docker exec $ContainerName redis-cli LASTSAVE 2>$null
docker exec $ContainerName redis-cli BGSAVE | Out-Null

$saved = $false
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 1
    $afterSave = docker exec $ContainerName redis-cli LASTSAVE 2>$null
    if ($afterSave -ne $beforeSave) {
        Write-Host "[INFO] BGSAVE completado (${i}s)."
        $saved = $true
        break
    }
}
if (-not $saved) { Write-Host "[WARN] BGSAVE no confirmado en 30s. Copiando de todas formas." }

# ── 4. Copiar dump.rdb ────────────────────────────────────────────────────
$backupFile = Join-Path $BackupDir "graphiti_$Timestamp.rdb"
$copied = $false
foreach ($dataPath in @("/var/lib/falkordb/data/dump.rdb", "/data/dump.rdb")) {
    docker exec $ContainerName test -f $dataPath 2>$null
    if ($LASTEXITCODE -eq 0) {
        docker cp "${ContainerName}:${dataPath}" $backupFile 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $backupFile)) {
            Write-Host "[OK] Backup guardado: $backupFile" -ForegroundColor Green
            $copied = $true
            break
        }
    }
}
if (-not $copied) {
    Write-Host "[ERR] No se pudo copiar dump.rdb. Backup FALLIDO." -ForegroundColor Red
    exit 1
}

# ── 5. Manifiesto (JSON válido — solo campos escalares) ──────────────────
$dbsizeRaw = docker exec $ContainerName redis-cli DBSIZE 2>$null
$dbsize = if ($dbsizeRaw -match '(\d+)') { [int]$Matches[1] } else { -1 }
$image = docker inspect --format '{{.Config.Image}}' $ContainerName 2>$null
if (-not $image) { $image = "unknown" }

$manifest = @{
    timestamp = $Timestamp
    hostname  = $Hostname
    container = $ContainerName
    image     = "$image"
    rdb_file  = "graphiti_$Timestamp.rdb"
    dbsize    = $dbsize
    restore   = "NO copiar dump.rdb a mano (AOF lo ignora). Usar restore-graph.ps1 / restore-graph.sh"
}
$manifestPath = Join-Path $BackupDir "graphiti_$Timestamp.manifest.json"
$manifest | ConvertTo-Json | Out-File $manifestPath -Encoding UTF8
Write-Host "[INFO] Manifiesto: $manifestPath (dbsize=$dbsize)"

# ── 6. Rotación (mantener últimos $MaxBackups) ────────────────────────────
$oldRdb = Get-ChildItem "$BackupDir\*.rdb" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups
$oldMan = Get-ChildItem "$BackupDir\*.manifest.json" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups
($oldRdb + $oldMan) | ForEach-Object { Remove-Item $_.FullName -Force }
if ($oldRdb) { Write-Host "[INFO] Backups viejos limpiados." }

$totalMB = [math]::Round(((Get-ChildItem $BackupDir | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "[INFO] Tamaño total de backups: $totalMB MB en $BackupDir"
Write-Host "[DONE] Backup completado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
