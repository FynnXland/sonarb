#Requires -Version 7
<#
.SYNOPSIS
    Baut das App-Bundle (AAB) von Sonarb für Google Play. Lädt nichts hoch.

.DESCRIPTION
    Sperren -> analyze + test -> flutter build appbundle --release.
    Gesperrt wird, wenn lokale Plugins eingebunden sind (die Play-Fassung ist die Grund-App
    ohne Plugins) oder wenn in lib/ noch eine Angabe mit "[ANGABE FEHLT" steht.
    Die Build-Nummer bleibt unverändert: Sie muss höher sein als die des letzten Uploads in der
    Play Console und wird bei Bedarf von Hand in pubspec.yaml erhöht.

.PARAMETER SkipChecks
    Überspringt analyze und Tests (die Sperren laufen immer).

.EXAMPLE
    tool/build-play.ps1
#>
param(
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$env:GRADLE_USER_HOME = Join-Path $env:USERPROFILE '.gradle'

$ProjektDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$PubspecPath = Join-Path $ProjektDir 'pubspec.yaml'
$PluginListe = Join-Path $ProjektDir 'lib/plugins/installed_plugins.dart'
$KeyProperties = Join-Path $env:USERPROFILE '.handy-keys\key.properties'

function Schritt($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Abbruch($t) { Write-Host "FEHLER: $t" -ForegroundColor Red; exit 1 }

Schritt 'Sperren'
if (-not (Test-Path $KeyProperties)) { Abbruch "Keystore fehlt: $KeyProperties" }

$plugins = Get-Content $PluginListe -Raw
if ($plugins -match "import\s+'local/") {
    Abbruch ("Lokale Plugins sind eingebunden ($PluginListe). " +
        "Die Play-Fassung enthält keine Plugins. Zurücksetzen: dart run tool/plugins.dart --reset")
}
if ($plugins -notmatch '=>\s*const\s*\[\s*\];') {
    Abbruch "$PluginListe ist nicht die leere Repository-Fassung. Zurücksetzen: dart run tool/plugins.dart --reset"
}

$offen = Get-ChildItem (Join-Path $ProjektDir 'lib') -Recurse -Filter '*.dart' |
    Select-String -SimpleMatch '[ANGABE FEHLT'
if ($offen) {
    $offen | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber)" }
    Abbruch 'Fehlende Angaben in lib/ (siehe oben), z. B. Name und Anschrift für die Datenschutzhinweise.'
}

$m = [regex]::Match((Get-Content $PubspecPath -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $m.Success) { Abbruch "Keine Zeile 'version: x.y.z+N' in pubspec.yaml." }
$versionName = $m.Groups[1].Value
$versionCode = $m.Groups[2].Value
Write-Host "Plugins: keine. Angaben: vollständig. Version $versionName ($versionCode)."

Push-Location $ProjektDir
try {
    if (-not $SkipChecks) {
        Schritt 'flutter analyze'
        flutter analyze
        if ($LASTEXITCODE -ne 0) { Abbruch 'flutter analyze meldet Befunde.' }
        Schritt 'flutter test'
        flutter test
        if ($LASTEXITCODE -ne 0) { Abbruch 'Tests fehlgeschlagen.' }
    }

    Schritt 'flutter build appbundle --release'
    flutter build appbundle --release --dart-define=SONARB_VERSION=$versionName
    if ($LASTEXITCODE -ne 0) { Abbruch 'Build fehlgeschlagen.' }
} finally {
    Pop-Location
}

$aab = Join-Path $ProjektDir 'build/app/outputs/bundle/release/app-release.aab'
if (-not (Test-Path $aab)) { Abbruch "AAB nicht gefunden: $aab" }
$groesse = [Math]::Round((Get-Item $aab).Length / 1MB, 1)

Write-Host ""
Write-Host "Fertig: $aab ($groesse MB), Version $versionName ($versionCode)."
Write-Host "Hochladen in der Play Console von Hand. versionCode $versionCode muss über dem letzten Upload liegen."
