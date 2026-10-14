# The equivalent of the desktop's `npm run check`. Stops at the first failing stage.
# Written for Windows PowerShell 5.1 as well as pwsh 7, so no `&&` or `??`.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$stages = @(
  @{ Name = 'analyze'; Run = { flutter analyze --fatal-infos } },
  @{ Name = 'format'; Run = { dart format --output=none --set-exit-if-changed . } },
  @{ Name = 'test'; Run = { flutter test } }
)

foreach ($stage in $stages) {
  Write-Host "== $($stage.Name)"
  & $stage.Run
  if ($LASTEXITCODE -ne 0) {
    Write-Host "check failed at: $($stage.Name)" -ForegroundColor Red
    exit $LASTEXITCODE
  }
}
Write-Host 'check passed' -ForegroundColor Green
