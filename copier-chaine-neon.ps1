<#
  Copie la chaine de connexion Neon (connexion directe) dans le presse-papiers.

  Utilisation :
      powershell -ExecutionPolicy Bypass -File .\copier-chaine-neon.ps1

  La chaine n'est jamais affichee : elle est placee dans le presse-papiers,
  prete a etre collee dans Render (champ DATABASE_URL).
#>

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
$fichier = Join-Path $racine '.env.local'

if (-not (Test-Path $fichier)) {
    Write-Host "Fichier introuvable : .env.local" -ForegroundColor Red
    Write-Host "Regénérez-le avec : neon env pull" -ForegroundColor Yellow
    exit 1
}

$ligne = Get-Content $fichier |
    Where-Object { $_ -match '^DATABASE_URL_UNPOOLED=' } |
    Select-Object -First 1

if (-not $ligne) {
    Write-Host "DATABASE_URL_UNPOOLED absent de .env.local." -ForegroundColor Red
    exit 1
}

$url = ($ligne -replace '^DATABASE_URL_UNPOOLED=', '').Trim().Trim('"').Trim("'")

if ($url -notmatch '^postgres(ql)?://') {
    Write-Host "La valeur lue n'est pas une chaine PostgreSQL valide." -ForegroundColor Red
    exit 1
}

try {
    Set-Clipboard -Value $url
    $copie = $true
} catch {
    $copie = $false
}

$hote = if ($url -match '@([^/:?]+)') { $Matches[1] } else { 'inconnu' }
$base = if ($url -match '://[^/]+/([^?]+)') { $Matches[1] } else { 'inconnue' }

Write-Host ""
if ($copie) {
    Write-Host "Chaine copiee dans le presse-papiers (non affichee)." -ForegroundColor Green
    Write-Host "Collez-la dans Render, champ DATABASE_URL." -ForegroundColor Green
} else {
    Write-Host "Copie automatique impossible : ouvrez .env.local et copiez la" -ForegroundColor Yellow
    Write-Host "valeur de la ligne DATABASE_URL_UNPOOLED." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Verifications (sans divulguer le mot de passe) :" -ForegroundColor DarkGray
Write-Host "  hote        : $hote"
Write-Host "  base        : $base"
Write-Host "  SSL requis  : $([bool]($url -match 'sslmode=require'))"
Write-Host "  pooler      : $([bool]($url -match '-pooler'))  (doit etre False)"
