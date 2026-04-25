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

$entrypoint = Get-Content -LiteralPath (Join-Path $repoRoot "codex-continuum.ps1") -Raw
if ($entrypoint -notmatch "get-continuum-status\.ps1") {
    Add-Failure "Entrypoint does not expose the status command"
}

$testText = Get-Content -LiteralPath (Join-Path $repoRoot "tests\CodexContinuum.Tests.ps1") -Raw
if ($testText -match "\bShould\b") {
    Add-Failure "Pester tests use Should syntax; use explicit throw assertions for Pester 3 and 5 compatibility."
}

$watcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\codex-live-continue.ps1") -Raw
foreach ($required in @("SubmitConfirmMilliseconds", "sendkeys-tilde", "sendkeys-ctrl-m", "SendEnterKey", "SendEscapeKey", "-confirmed", "TitleWorkingPattern", "WorkingSignal", "ForceForegroundWindow", "Set-LiveSessionForeground", "prompt_attempts", "confirmed_work_observed", "send_confirmation", "RequireObservedWorkingBeforeFirstPrompt", "observedWorking = -not")) {
    if ($watcher -notmatch [regex]::Escape($required)) {
        Add-Failure "Watcher missing required submit behavior: $required"
    }
}

$packager = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\package-plugin.ps1") -Raw
foreach ($required in @("Compress-Archive", "PACKAGE-MANIFEST.json", ".codex-plugin", "SHA256")) {
    if ($packager -notmatch [regex]::Escape($required)) {
        Add-Failure "Packager missing required behavior: $required"
    }
}

$statusScriptPath = Join-Path $repoRoot "scripts\get-continuum-status.ps1"
if (-not (Test-Path -LiteralPath $statusScriptPath)) {
    Add-Failure "Status script is missing"
}
else {
    $statusScript = Get-Content -LiteralPath $statusScriptPath -Raw
    foreach ($required in @("Get-ContinuumSummary", "IdleStale", "LastPrompt", "Watcher", "Target", "ReceiptParseFailures")) {
        if ($statusScript -notmatch [regex]::Escape($required)) {
            Add-Failure "Status script missing required behavior: $required"
        }
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
