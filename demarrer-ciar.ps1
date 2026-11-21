<#
  Demarre CIAR-Mali (API FastAPI + interface Flutter Web).

  Utilisation :
      powershell -ExecutionPolicy Bypass -File .\demarrer-ciar.ps1

  Options :
      -Port 8001        port d'ecoute (8001 par defaut)
      -Rechargement     recharge automatiquement le serveur a chaque modification
      -SansNavigateur   n'ouvre pas le navigateur

  URL : http://127.0.0.1:8001/app/   (docs : http://127.0.0.1:8001/docs)
#>
param(
    [int]$Port = 8001,
    [switch]$Rechargement,
    [switch]$SansNavigateur
)

$ErrorActionPreference = 'Stop'

$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path $racine 'backend'
$python = Join-Path (Split-Path -Parent $racine) '.venv\Scripts\python.exe'

if (-not (Test-Path $python)) {
    Write-Host "Python introuvable : $python" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $backend 'app\main.py'))) {
    Write-Host "Projet introuvable : $backend" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $racine 'frontend\build\web\index.html'))) {
    Write-Host "Attention : l'interface web n'est pas compilee." -ForegroundColor Yellow
    Write-Host "Lancez d'abord : frontend\build_web.ps1" -ForegroundColor Yellow
}

$occupe = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($occupe) {
    Write-Host "Le port $Port est deja utilise (PID $($occupe[0].OwningProcess))." -ForegroundColor Yellow
    Write-Host "Arretez ce processus ou choisissez un autre port : -Port 8010" -ForegroundColor Yellow
    exit 1
}

$arguments = @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', "$Port")
if ($Rechargement) { $arguments += '--reload' }

Write-Host "Demarrage de CIAR-Mali sur le port $Port..." -ForegroundColor Cyan
Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $backend

$pret = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
        $pret = $true
        break
    }
}

if (-not $pret) {
    Write-Host "Le serveur n'a pas demarre. Verifiez la fenetre qui vient de s'ouvrir." -ForegroundColor Red
    exit 1
}

$url = "http://127.0.0.1:$Port/app/"
Write-Host "CIAR-Mali est disponible : $url" -ForegroundColor Green
Write-Host "Documentation API      : http://127.0.0.1:$Port/docs"

if (-not $SansNavigateur) { Start-Process $url }

