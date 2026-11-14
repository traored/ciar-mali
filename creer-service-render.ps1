<#
  Cree le service Render Â« ciar-mali Â» via l'API Render.

  Utilisation :
      powershell -ExecutionPolicy Bypass -File .\creer-service-render.ps1

  La cle API est lue depuis un fichier local (jamais affichee) :
      C:\Users\HP\AppData\Local\Temp\opencode\render-key.txt
  ou depuis la variable d'environnement RENDER_API_KEY.

  La chaine Neon (DATABASE_URL) est lue dans .env.local, connexion directe.
#>
param(
    [string]$Nom = "ciar-mali",
    [string]$Depot = "https://github.com/traored/Gestion_edt_et_notes",
    [string]$Branche = "main",
    [string]$Region = "frankfurt",
    [switch]$Simulation
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$racine = Split-Path -Parent $MyInvocation.MyCommand.Path
$api = "https://api.render.com/v1"

# ---------------------------------------------------------------- Cle API
$cle = $env:RENDER_API_KEY
if (-not $cle) {
    $fichierCle = Join-Path $env:TEMP "opencode\render-key.txt"
    if (Test-Path $fichierCle) {
        $cle = (Get-Content $fichierCle -Raw).Trim()
    }
}
if (-not $cle) {
    Write-Host "Cle API Render introuvable." -ForegroundColor Red
    Write-Host "Creez-en une sur https://dashboard.render.com/u/settings#api-keys" -ForegroundColor Yellow
    Write-Host "puis enregistrez-la dans : $env:TEMP\opencode\render-key.txt" -ForegroundColor Yellow
    exit 1
}

$entetes = @{
    Authorization  = "Bearer $cle"
    Accept         = "application/json"
    "Content-Type" = "application/json"
}

function Appeler-Api {
    param(
        [string]$Methode,
        [string]$Chemin,
        $Corps
    )
    $parametres = @{
        Method      = $Methode
        Uri         = "$api$Chemin"
        Headers     = $entetes
        ErrorAction = 'Stop'
    }
    if ($null -ne $Corps) {
        $parametres.Body = ($Corps | ConvertTo-Json -Depth 8 -Compress)
    }
    try {
        return Invoke-RestMethod @parametres
    } catch {
        $reponse = $_.Exception.Response
        $detail = ""
        if ($reponse) {
            try {
                $lecteur = New-Object System.IO.StreamReader($reponse.GetResponseStream())
                $detail = $lecteur.ReadToEnd()
                $lecteur.Close()
            } catch { }
        }
        throw "API Render $Methode $Chemin -> $($_.Exception.Message) $detail"
    }
}

# ---------------------------------------------------------------- Chaine Neon
$fichierEnv = Join-Path $racine ".env.local"
if (-not (Test-Path $fichierEnv)) {
    Write-Host ".env.local introuvable : lancez d'abord 'neon env pull'." -ForegroundColor Red
    exit 1
}
$ligneDb = Get-Content $fichierEnv |
    Where-Object { $_ -match '^DATABASE_URL_UNPOOLED=' } |
    Select-Object -First 1
if (-not $ligneDb) {
    Write-Host "DATABASE_URL_UNPOOLED absent de .env.local." -ForegroundColor Red
    exit 1
}
$chaineDb = ($ligneDb -replace '^DATABASE_URL_UNPOOLED=', '').Trim().Trim('"').Trim("'")
if ($chaineDb -notmatch '^postgres(ql)?://') {
    Write-Host "Chaine Neon invalide dans .env.local." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- Espace de travail
$espaces = Appeler-Api -Methode GET -Chemin "/owners?limit=20"
$proprietaire = $null
foreach ($element in $espaces) {
    $o = if ($element.owner) { $element.owner } else { $element }
    if ($o.id) { $proprietaire = $o; break }
}
if (-not $proprietaire) {
    Write-Host "Aucun espace de travail Render trouve pour cette cle." -ForegroundColor Red
    exit 1
}
Write-Host "Espace de travail : $($proprietaire.name) ($($proprietaire.id))" -ForegroundColor DarkGray

# ---------------------------------------------------------------- Service deja cree ?
$existants = Appeler-Api -Methode GET -Chemin "/services?limit=100"
$service = $null
foreach ($element in $existants) {
    $s = if ($element.service) { $element.service } else { $element }
    if ($s.name -eq $Nom) { $service = $s; break }
}

if ($service) {
    Write-Host "Le service '$Nom' existe deja : $($service.serviceDetails.url)" -ForegroundColor Yellow
} else {
    $corps = @{
        type       = "web_service"
        name       = $Nom
        ownerId    = $proprietaire.id
        repo       = $Depot
        branch     = $Branche
        autoDeploy = "yes"
        envVars    = @(
            @{ key = "DATABASE_URL"; value = $chaineDb },
            @{ key = "SECRET_KEY"; generateValue = $true },
            @{ key = "TOKEN_EXPIRATION_MINUTES"; value = "480" },
            @{ key = "CORS_ORIGINS"; value = "https://$Nom.onrender.com" }
        )
        serviceDetails = @{
            runtime            = "docker"
            plan               = "free"
            region             = $Region
            healthCheckPath    = "/api/sante"
            numInstances       = 1
            envSpecificDetails = @{ dockerfilePath = "./Dockerfile" }
        }
    }

    if ($Simulation) {
        Write-Host "[simulation] service $Nom / $Region / plan free" -ForegroundColor Cyan
        exit 0
    }

    Write-Host "Creation du service '$Nom' (region $Region, plan free)..." -ForegroundColor Cyan
    try {
        $service = Appeler-Api -Methode POST -Chemin "/services" -Corps $corps
    } catch {
        if ("$_" -match 'repo|github|build source|not connected|not found') {
            Write-Host ""
            Write-Host "Le depot GitHub n'est pas encore relie a Render." -ForegroundColor Red
            Write-Host "Installez l'application GitHub de Render sur le depot :" -ForegroundColor Yellow
            Write-Host "  https://dashboard.render.com/select-repo?type=web" -ForegroundColor Yellow
            Write-Host "puis relancez ce script." -ForegroundColor Yellow
        }
        throw
    }
    if ($service.service) { $service = $service.service }
    Write-Host "Service cree : $($service.id)" -ForegroundColor Green
}

$url = $service.serviceDetails.url
if (-not $url) { $url = "https://$Nom.onrender.com" }
Write-Host ""
Write-Host "URL : $url" -ForegroundColor Green
Write-Host ""
Write-Host "Le premier deploiement prend 5 a 10 minutes (construction de l'image)." -ForegroundColor DarkGray
Write-Host "Suivez-le sur https://dashboard.render.com/web/$($service.id)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Verification une fois le deploiement termine :" -ForegroundColor DarkGray
Write-Host "  powershell -ExecutionPolicy Bypass -File .\verifier-en-ligne.ps1 -Url $url"
