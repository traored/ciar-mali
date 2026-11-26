<#
  Republie le code dans le depot public miroir utilise par Render.

  Utilisation :
      powershell -ExecutionPolicy Bypass -File .\publier-miroir.ps1
      powershell -ExecutionPolicy Bypass -File .\publier-miroir.ps1 -Message "Correction des notes"

  Le miroir ne contient qu'un instantane du code (un seul commit, sans
  historique) : ni la base locale, ni les fichiers .env, ni les cles.
  Render redeploie apres la publication : le script declenche le
  deploiement par l'API (le webhook GitHub n'est pas toujours installe).
#>
param(
    [string]$Depot = "https://github.com/traored/ciar-mali",
    [string]$Message = "Mise a jour",
    [string]$Service = "srv-dbp7u4utlv9c73eptcf0"
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
$temporaire = Join-Path $env:TEMP "opencode\ciar-miroir-publication"

if (-not (Test-Path (Join-Path $racine ".git"))) {
    Write-Host "Ce script doit etre lance depuis le depot du projet." -ForegroundColor Red
    exit 1
}

$etat = git -C $racine status --porcelain
if ($etat) {
    Write-Host "Des modifications ne sont pas encore commitees :" -ForegroundColor Yellow
    $etat | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host "Le miroir ne contient que les commits : commitez d'abord." -ForegroundColor Yellow
    exit 1
}

if (Test-Path $temporaire) { Remove-Item $temporaire -Recurse -Force }
New-Item -ItemType Directory -Path $temporaire | Out-Null

$archive = Join-Path $env:TEMP "opencode\ciar-miroir.tar"
git -C $racine archive --format=tar HEAD -o $archive
tar -xf $archive -C $temporaire
Remove-Item $archive -Force

Push-Location $temporaire
try {
    git init -q
    git checkout -q -b main
    git add -A
    git -c user.name="CIAR-Mali" -c user.email="deploy@ciar-mali.local" `
        -c core.safecrlf=false commit -q -m $Message
    git remote add origin $Depot
    Write-Host "Publication vers $Depot ..." -ForegroundColor Cyan
    git push --force origin main
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($code -ne 0) {
    Write-Host "La publication a echoue (code $code)." -ForegroundColor Red
    exit $code
}

# Declenche le deploiement Render. La cle est lue dans la variable
# d'environnement RENDER_API_KEY, sinon dans le fichier local du poste.
$cle = $env:RENDER_API_KEY
if (-not $cle) {
    $fichier = Join-Path $env:TEMP "opencode\render-key.txt"
    if (Test-Path $fichier) { $cle = (Get-Content $fichier -Raw).Trim() }
}

if ($cle) {
    try {
        $corps = @{ clearCache = "do_not_clear" } | ConvertTo-Json
        $deploiement = Invoke-RestMethod `
            -Uri "https://api.render.com/v1/services/$Service/deploys" `
            -Method POST `
            -Headers @{ Authorization = "Bearer $cle"; Accept = 'application/json' } `
            -ContentType "application/json" `
            -Body $corps `
            -TimeoutSec 60
        Write-Host "Deploiement Render lance : $($deploiement.id) ($($deploiement.status))" -ForegroundColor Green
    } catch {
        Write-Host "Le declenchement automatique a echoue : $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Lancez-le depuis https://dashboard.render.com/web/$Service" -ForegroundColor Yellow
    }
} else {
    Write-Host "Pas de cle Render : lancez le deploiement depuis le tableau de bord." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Miroir publie." -ForegroundColor Green
Write-Host "Suivi : https://dashboard.render.com/web/$Service" -ForegroundColor DarkGray
