<#
  Copie les donnees locales (SQLite) vers la base PostgreSQL de production.

  Utilisation :
      powershell -ExecutionPolicy Bypass -File .\migrer-vers-postgres.ps1

  Le script demande la chaine de connexion Neon, verifie qu'elle est complete,
  utilise automatiquement le Python du projet (.venv) puis lance la migration.

  Options :
      -Cible "postgresql://..."   evite la saisie interactive
      -Conserver                  n'efface pas la base cible avant la copie
#>
param(
    [string]$Cible,
    [string]$Source = "sqlite:///./edt.db",
    [switch]$Conserver
)

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path $racine 'backend'
$python = Join-Path (Split-Path -Parent $racine) '.venv\Scripts\python.exe'

if (-not (Test-Path $python)) {
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
}
if (-not $python) {
    Write-Host "Python introuvable. Installez Python 3.12 ou creez le venv du projet." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $backend 'edt.db'))) {
    Write-Host "Base locale introuvable : backend\edt.db" -ForegroundColor Red
    exit 1
}

if (-not $Cible) {
    Write-Host ""
    Write-Host "Collez la chaine de connexion Neon (bouton Connect > Connection string) :" -ForegroundColor Cyan
    Write-Host "ex. postgresql://neondb_owner:motdepasse@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require" -ForegroundColor DarkGray
    $Cible = Read-Host "Chaine"
}

$Cible = $Cible.Trim().Trim('"').Trim("'")

if ($Cible -match 'URL Neon|<.*>|\.\.\.') {
    Write-Host ""
    Write-Host "La chaine contient encore un texte d'exemple (<URL Neon>, ...)." -ForegroundColor Red
    Write-Host "Copiez la vraie chaine depuis le tableau de bord Neon." -ForegroundColor Yellow
    exit 1
}
if ($Cible -notmatch '^postgres(ql)?://') {
    Write-Host "La chaine doit commencer par postgresql://" -ForegroundColor Red
    exit 1
}
$locale = $Cible -match '@(localhost|127\.0\.0\.1)'
if (-not $locale) {
    if ($Cible -notmatch '://[^:]+:[^@]+@') {
        Write-Host "Chaine incomplete : le mot de passe semble absent." -ForegroundColor Red
        exit 1
    }
    if ($Cible -notmatch 'sslmode=') {
        Write-Host "Chaine incomplete : ajoutez ?sslmode=require a la fin." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Source : $Source" -ForegroundColor DarkGray
Write-Host "Cible  : $($Cible -replace '://[^:]+:[^@]+@', '://***:***@')" -ForegroundColor DarkGray
Write-Host ""

$arguments = @('-m', 'outils.migrer_donnees', '--source', $Source, '--cible', $Cible)
if (-not $Conserver) { $arguments += '--vider' }

Push-Location $backend
try {
    & $python @arguments
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($code -ne 0) {
    Write-Host ""
    Write-Host "La migration a echoue (code $code)." -ForegroundColor Red
    exit $code
}

Write-Host ""
Write-Host "Migration terminee. Redeployez le service Render (Manual Deploy)" -ForegroundColor Green
Write-Host "pour que l'application redemarre sur les donnees copiees." -ForegroundColor Green
