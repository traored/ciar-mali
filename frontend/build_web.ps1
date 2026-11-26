# Compile l'interface Flutter Web et versionne les fichiers JavaScript.
# Le versionnage évite que les navigateurs réutilisent une ancienne interface
# après une mise à jour.
param(
    [string]$BaseHref = "/app/"
)

$ErrorActionPreference = "Stop"
$frontend = $PSScriptRoot
$flutter = "C:\flutter\bin\flutter.bat"

Write-Host "Compilation de l'interface Flutter Web…"
# `--no-web-resources-cdn` sert CanvasKit depuis le serveur local : l'interface
# fonctionne même sans accès Internet (réseaux d'université filtrés).
$processus = Start-Process -FilePath $flutter `
    -ArgumentList @("build", "web", "--release", "--base-href=$BaseHref", "--no-web-resources-cdn") `
    -WorkingDirectory $frontend -NoNewWindow -Wait -PassThru

if ($processus.ExitCode -ne 0) {
    throw "La compilation Flutter a échoué (code $($processus.ExitCode))."
}

$web = Join-Path $frontend "build\web"
$main = Join-Path $web "main.dart.js"
if (-not (Test-Path $main)) {
    throw "Fichier introuvable : $main"
}

$version = (Get-FileHash $main -Algorithm SHA1).Hash.Substring(0, 10).ToLowerInvariant()
$utf8 = New-Object System.Text.UTF8Encoding($false)

$bootstrap = Join-Path $web "flutter_bootstrap.js"
$contenu = [IO.File]::ReadAllText($bootstrap)
# Selon la version de Flutter, le chemin est écrit "mainJsPath":"…" (ancien)
# ou mainJsPath??"…" (récent). On gère les deux formes.
$contenu = $contenu.Replace(
    '"mainJsPath":"main.dart.js"',
    '"mainJsPath":"main.dart.js?v=' + $version + '"'
)
$contenu = $contenu.Replace(
    'mainJsPath??"main.dart.js"',
    'mainJsPath??"main.dart.js?v=' + $version + '"'
)
[IO.File]::WriteAllText($bootstrap, $contenu, $utf8)

$index = Join-Path $web "index.html"
$contenu = [IO.File]::ReadAllText($index)
$contenu = $contenu.Replace(
    'src="flutter_bootstrap.js"',
    'src="flutter_bootstrap.js?v=' + $version + '"'
)
[IO.File]::WriteAllText($index, $contenu, $utf8)

Write-Host "Interface compilée : build\web (version $version)" -ForegroundColor Green
