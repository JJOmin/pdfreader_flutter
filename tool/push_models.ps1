# Copies the speech models to the phone's app storage over adb (ADR 1, section 2, option B).
#   powershell -ExecutionPolicy Bypass -File tool/push_models.ps1 [-From <models folder>]
# The default source is the desktop's models folder, filled there by `npm run models`.
param([string]$From = (Join-Path $PSScriptRoot '..\..\pdfreader\models'))
$ErrorActionPreference = 'Stop'

$target = '/sdcard/Android/data/io.github.jjomin.pdfreader/files/models'
# Folder names as in the desktop's models.json. Files the phone never reads are left out:
# Kokoro's Chinese dictionary and rules, and the recogniser's sample recordings.
$models = @{
  'kokoro-multi-lang-v1_0'                                      = @('dict', 'lexicon-zh.txt', '*.fst')
  'vits-piper-de_DE-thorsten-high'                              = @()
  'sherpa-onnx-nemo-fast-conformer-ctc-en-de-es-fr-14288-int8'  = @('test_wavs')
}

if (-not ((adb devices) -match "`tdevice$")) { throw 'No phone connected and authorised (adb devices).' }
foreach ($name in $models.Keys) {
  $source = Join-Path $From $name
  if (-not (Test-Path $source)) { throw "Missing $source. Run npm run models in the desktop project." }
  Write-Host "== $name"
  adb shell mkdir -p "$target/$name" | Out-Null
  foreach ($entry in Get-ChildItem $source) {
    $skip = $models[$name] | Where-Object { $entry.Name -like $_ }
    if ($skip) { continue }
    adb push $entry.FullName "$target/$name/" | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0) { throw "adb push failed for $($entry.FullName)" }
  }
}
adb shell du -sh $target
