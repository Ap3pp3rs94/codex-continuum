[CmdletBinding()]
param()

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter "*.ps1" |
    ForEach-Object {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            Add-Failure "Parse failed: $($_.FullName)"
        }
    }

try {
    Get-Content -LiteralPath (Join-Path $repoRoot ".codex-plugin\plugin.json") -Raw | ConvertFrom-Json | Out-Null
}
catch {
    Add-Failure "plugin.json is not valid JSON"
}

$watcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\codex-live-continue.ps1") -Raw
foreach ($required in @("SubmitConfirmMilliseconds", "sendkeys-tilde", "sendkeys-ctrl-m", "SendEnterKey", "SendEscapeKey", "-confirmed", "TitleWorkingPattern", "WorkingSignal", "ForceForegroundWindow", "Set-LiveSessionForeground", "prompt_attempts", "RequireObservedWorkingBeforeFirstPrompt", "observedWorking = -not")) {
    if ($watcher -notmatch [regex]::Escape($required)) {
        Add-Failure "Watcher missing required submit behavior: $required"
    }
}

$repoText = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object {
        $_.FullName -notmatch "\\data\\" -and
        $_.FullName -notmatch "\\.git\\" -and
        $_.FullName -notmatch "\\tests\\" -and
        $_.FullName -notmatch "\\scripts\\validate\.ps1$"
    } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }

if (($repoText -join "`n") -match "FrancisLiveWindow|start-codex-continuity") {
    Add-Failure "Old project-specific identifiers found"
}

$pester = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
if ($pester) {
    $pesterResult = Invoke-Pester -Path (Join-Path $repoRoot "tests") -PassThru
    if ($pesterResult.FailedCount -gt 0) {
        Add-Failure "Pester failed: $($pesterResult.FailedCount) failing test(s)"
    }
}
else {
    Write-Host "Pester not installed; skipped Pester tests."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Codex Continuum validation passed."
