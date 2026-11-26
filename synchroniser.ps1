<#
  Copie ponctuelle et explicite entre les bases du projet.

  Sens possibles :
    sqlite-vers-mysql   SQLite local -> MySQL (base edt_backup)
    mysql-vers-sqlite   MySQL -> SQLite local
    sqlite-vers-neon    SQLite local -> Neon (production)
    neon-vers-sqlite    Neon -> SQLite local

  AVERTISSEMENT : la cible est entierement remplacee. Arretez le serveur local
  avant une copie dont la cible est SQLite.

  Exemples :
    powershell -ExecutionPolicy Bypass -File .\synchroniser.ps1 -Sens sqlite-vers-mysql
    powershell -ExecutionPolicy Bypass -File .\synchroniser.ps1 -Sens neon-vers-sqlite
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "sqlite-vers-mysql",
        "mysql-vers-sqlite",
        "sqlite-vers-neon",
        "neon-vers-sqlite"
    )]
    [string]$Sens,

    [string]$SqliteFichier = ".\edt.db",

    [string]$Neon,

    [string]$MysqlHost = "localhost",
    [string]$MysqlPort = "3306",
    [string]$MysqlUser = "traored",
    [string]$MysqlBase = "edt_backup",

    [switch]$Forcer
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path $racine 'backend'
$python = Join-Path (Split-Path -Parent $racine) '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
}
if (-not $python) { throw "Python introuvable. Creez le venv du projet." }
if (-not (Test-Path (Join-Path $backend 'outils\migrer_donnees.py'))) {
    throw "Outil de migration introuvable dans backend\\outils."
}

function Masquer([string]$url) {
    return ($url -replace '://[^:]+:[^@]+@', '://***:***@')
}

# --- SQLite -----------------------------------------------------------------
$sqlitePath = if ([System.IO.Path]::IsPathRooted($SqliteFichier)) {
    $SqliteFichier
} else {
    Join-Path $backend $SqliteFichier
}
$sqliteUrl = "sqlite:///" + ($sqlitePath -replace '\\', '/')

# --- Neon -------------------------------------------------------------------
$neonUrl = $Neon
if (-not $neonUrl -and ($Sens -like '*-neon' -or $Sens -like 'neon-*')) {
    $config = Join-Path $backend '.env'
    if (-not (Test-Path $config)) { $config = Join-Path $backend '.env.bak' }
    if (Test-Path $config) {
        $ligne = (Select-String -Path $config -Pattern '^DATABASE_URL=' | Select-Object -First 1).Line
        if ($ligne) {
            $neonUrl = ($ligne -replace '^DATABASE_URL=', '').Trim().Trim('"').Trim("'")
        }
    }
}
if (($Sens -like '*-neon' -or $Sens -like 'neon-*') -and $neonUrl -notmatch '^postgres(ql)?://') {
    throw "URL Neon introuvable ou invalide. Passez-la avec -Neon ou verifiez backend\\.env."
}

# --- MySQL ------------------------------------------------------------------
$mysqlUrl = $null
if ($Sens -like '*mysql') {
    $mdpSecret = Read-Host "Mot de passe MySQL ($MysqlUser)" -AsSecureString
    $mdp = [System.Net.NetworkCredential]::new('', $mdpSecret).Password
    $mysqlUrl = "mysql+pymysql://{0}:{1}@{2}:{3}/{4}?charset=utf8mb4" -f `
        [uri]::EscapeDataString($MysqlUser),
        [uri]::EscapeDataString($mdp),
        $MysqlHost,
        $MysqlPort,
        $MysqlBase
}

# --- Choix source / cible ----------------------------------------------------
switch ($Sens) {
    'sqlite-vers-mysql' { $source = $sqliteUrl; $cible = $mysqlUrl }
    'mysql-vers-sqlite' { $source = $mysqlUrl; $cible = $sqliteUrl }
    'sqlite-vers-neon'  { $source = $sqliteUrl; $cible = $neonUrl }
    'neon-vers-sqlite'  { $source = $neonUrl;  $cible = $sqliteUrl }
}

if ($source -eq $cible) { throw "La source et la cible sont identiques." }
if ($Sens -like 'sqlite-*' -and -not (Test-Path $sqlitePath)) {
    throw "Base SQLite source introuvable : $sqlitePath"
}

Write-Host ""
Write-Host "Sens      : $Sens" -ForegroundColor Cyan
Write-Host "Source    : $(Masquer $source)" -ForegroundColor DarkGray
Write-Host "Cible     : $(Masquer $cible)" -ForegroundColor DarkGray
Write-Host "ATTENTION : la cible sera entierement remplacee." -ForegroundColor Red
if ($cible -eq $sqliteUrl) {
    Write-Host "Arretez le serveur local avant de continuer." -ForegroundColor Yellow
}
Write-Host ""

if (-not $Forcer) {
    $reponse = Read-Host "Tapez OUI pour confirmer"
    if ($reponse -ne 'OUI') {
        Write-Host "Copie annulee."
        exit 1
    }
}

$arguments = @('-m', 'outils.migrer_donnees', '--source', $source, '--cible', $cible, '--vider')
Push-Location $backend
try {
    & $python @arguments
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($code -ne 0) { throw "La copie a echoue (code $code)." }
Write-Host ""
Write-Host "Copie terminee." -ForegroundColor Green
