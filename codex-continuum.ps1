$ErrorActionPreference = "Stop"

$routeArgs = @($args)
if ($routeArgs.Count -gt 0) {
    $command = ([string]$routeArgs[0]).TrimStart("-").ToLowerInvariant()
    $commandScripts = @{
        "start" = "scripts\start-continuum.ps1"
        "start-continuum" = "scripts\start-continuum.ps1"
        "status" = "scripts\get-continuum-status.ps1"
        "get-status" = "scripts\get-continuum-status.ps1"
        "get-continuum-status" = "scripts\get-continuum-status.ps1"
        "get-continuumstatus" = "scripts\get-continuum-status.ps1"
        "stop" = "scripts\stop-continuum.ps1"
        "stop-continuum" = "scripts\stop-continuum.ps1"
        "update" = "scripts\update-continuum.ps1"
        "update-continuum" = "scripts\update-continuum.ps1"
    }

    if ($commandScripts.ContainsKey($command)) {
        $commandScript = Join-Path $PSScriptRoot $commandScripts[$command]
        if (-not (Test-Path -LiteralPath $commandScript)) {
            throw "Continuum command script is missing: $commandScript"
        }

        $commandArgs = @()
        if ($routeArgs.Count -gt 1) {
            $commandArgs = @($routeArgs[1..($routeArgs.Count - 1)])
        }

        & $commandScript @commandArgs
        if (-not $?) {
            exit 1
        }

        if ($LASTEXITCODE -is [int]) {
            exit $LASTEXITCODE
        }

        exit 0
    }
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
