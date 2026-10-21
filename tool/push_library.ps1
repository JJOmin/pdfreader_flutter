# Copies documents the desktop prepared for the phone into the app's storage over adb (PLAN 1.9).
#   powershell -ExecutionPolicy Bypass -File tool/push_library.ps1 [-From <phone-library folder>] [-Only <docId>]
# The default source is the desktop app's library in its user data folder ("Add this document"
# in its Phone dialog). Each document is copied whole and replaces the phone's copy.
param(
  [string]$From = (Join-Path $env:APPDATA 'pdfreader\phone-library'),
  [string]$Only
)
$ErrorActionPreference = 'Stop'

$target = '/sdcard/Android/data/io.github.jjomin.pdfreader/files/library'
if (-not ((adb devices) -match "`tdevice$")) { throw 'No phone connected and authorised (adb devices).' }
if (-not (Test-Path $From)) { throw "No library at $From. Prepare a document in the desktop app first." }

$documents = Get-ChildItem $From -Directory | Where-Object {
  $_.Name -match '^[0-9a-f]{64}$' -and (Test-Path (Join-Path $_.FullName 'manifest.json'))
}
if ($Only) { $documents = $documents | Where-Object { $_.Name -eq $Only } }
if (-not $documents) { throw "No complete document in $From (a folder with a manifest.json)." }

adb shell mkdir -p $target | Out-Null
foreach ($document in $documents) {
  $name = (Get-Content (Join-Path $document.FullName 'manifest.json') -Raw | ConvertFrom-Json).name
  Write-Host "== $name ($($document.Name))"
  # Audio left over from an earlier preparation must not stay behind.
  adb shell rm -rf "$target/$($document.Name)" | Out-Null
  adb push $document.FullName "$target/" | Select-Object -Last 1
  if ($LASTEXITCODE -ne 0) { throw "adb push failed for $($document.FullName)" }
}
adb shell du -sh $target
