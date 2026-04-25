$ErrorActionPreference = "Stop"

$launcher = Join-Path $PSScriptRoot "scripts\start-codex-continuum.ps1"
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Continuum launcher is missing: $launcher"
}

& $launcher @args
if (-not $?) {
    exit 1
}

if ($LASTEXITCODE -is [int]) {
    exit $LASTEXITCODE
}

exit 0
