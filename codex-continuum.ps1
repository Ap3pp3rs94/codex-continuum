$ErrorActionPreference = "Stop"

$routeArgs = @($args)
if ($routeArgs.Count -gt 0 -and $routeArgs[0] -in @("status", "get-status", "-Status", "--status")) {
    $statusScript = Join-Path $PSScriptRoot "scripts\get-continuum-status.ps1"
    if (-not (Test-Path -LiteralPath $statusScript)) {
        throw "Continuum status script is missing: $statusScript"
    }

    $statusArgs = @()
    if ($routeArgs.Count -gt 1) {
        $statusArgs = @($routeArgs[1..($routeArgs.Count - 1)])
    }

    & $statusScript @statusArgs
    if (-not $?) {
        exit 1
    }

    if ($LASTEXITCODE -is [int]) {
        exit $LASTEXITCODE
    }

    exit 0
}

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
