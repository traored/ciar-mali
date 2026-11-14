<#
  Verifie une instance deployee de CIAR-Mali.

  Utilisation :
      powershell -ExecutionPolicy Bypass -File .\verifier-en-ligne.ps1 -Url https://ciar-mali.onrender.com
#>
param(
    [string]$Url,
    [string]$Identifiant = "admin",
    [string]$MotDePasse = "admin123"
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
    Write-Host "Python introuvable." -ForegroundColor Red
    exit 1
}

if (-not $Url) {
    $Url = Read-Host "URL du service Render (ex. https://ciar-mali.onrender.com)"
}
$Url = $Url.Trim().Trim('"').Trim("'").TrimEnd('/')

if ($Url -notmatch '^https?://') {
    Write-Host "L'URL doit commencer par https://" -ForegroundColor Red
    exit 1
}

Write-Host "Premier appel : le service gratuit peut mettre 30 a 60 s a se reveiller." -ForegroundColor DarkGray

Push-Location $backend
try {
    & $python -m outils.verifier_deploiement --url $Url --identifiant $Identifiant --mot-de-passe $MotDePasse
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
