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
foreach ($required in @("scripts\start-continuum.ps1", "scripts\stop-continuum.ps1", "scripts\get-continuum-status.ps1", "scripts\update-continuum.ps1")) {
    if ($entrypoint -notmatch [regex]::Escape($required)) {
        Add-Failure "Entrypoint missing command route: $required"
    }
}

$testText = Get-Content -LiteralPath (Join-Path $repoRoot "tests\CodexContinuum.Tests.ps1") -Raw
if ($testText -match "\bShould\b") {
    Add-Failure "Pester tests use Should syntax; use explicit throw assertions for Pester 3 and 5 compatibility."
}

$watcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\codex-live-continue.ps1") -Raw
foreach ($required in @("SubmitConfirmMilliseconds", "StableClearMilliseconds = 5000", "sendkeys-tilde", "sendkeys-ctrl-m", "SendEnterKey", "SendEscapeKey", "-confirmed", "TitleWorkingPattern", "WorkingSignal", "ForceForegroundWindow", "Set-LiveSessionForeground", "prompt_attempts", "MaxFailedSubmitAttempts", "consecutive_failed_submit_attempts", "repeated_failed_submit", "StuckWorkingSeconds", "ResyncCooldownSeconds", "Get-StatusSnapshotHash", "Sync-LiveSessionHandle", "staleWorkingIgnoreHash", "stale_text_resync", "codex_live_continue.resynced", "DisableQuickEditMode", "Disable-WatcherConsoleQuickEdit", "codex_live_continue.console_mode", "KillFlagPath", "kill_flag", "confirmed_work_observed", "send_confirmation", "RequireObservedWorkingBeforeFirstPrompt", "observedWorking = -not", '[string]$StatusPattern = "(?m)^\s*Working\s*$', '[string]$BackgroundWaitPattern = "(?m)^\s*Waiting for background', "-cmatch `$StatusPattern", "-cmatch `$BackgroundWaitPattern", "background_wait", "Clear-ConsoleSelectionMode", "codex_live_continue.selection_mode_cleared", "UsageWarningPattern", "UsagePauseFallbackSeconds", "Get-UsagePauseState", "Test-ActionableUsageWarningContext", "try again", "reached", "codex_live_continue.usage_paused", "codex_live_continue.usage_resumed", "AutoSelectApprovalChoice", "ApprovalPromptPattern", "InteractivePromptBlockPattern", "would you like to run", "DoNotAskAgainApprovalPattern", "DoNotAskAgainApprovalChoice", "FullWindow", "full_window_tail", "not_scanned_working", "Get-ApprovalPromptMatch", "Get-InteractivePromptBlock", "Send-ApprovalChoice", "codex_live_continue.approval_choice", "codex_live_continue.interactive_prompt_blocked")) {
    if ($watcher -notmatch [regex]::Escape($required)) {
        Add-Failure "Watcher missing required submit behavior: $required"
    }
}

if ($watcher -match '\$titleLooksInteractive') {
    Add-Failure "Watcher still treats a Select title alone as an interactive prompt."
}

$launcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\start-codex-continuum.ps1") -Raw
foreach ($required in @("Read-InteractiveTargetProcessId", "Read-InteractiveSessionId", "Resolve-LiveCodexWindowCandidateFromProcessId", "Target visible Codex PowerShell PID", "Session/thread id", "NonInteractive", "MaxFailedSubmitAttempts", "KillFlagPath", "AutoSelectApprovalChoice", "ApprovalChoice", "DoNotAskAgainApprovalChoice", "ApprovalPromptPattern", "InteractivePromptBlockPattern")) {
    if ($launcher -notmatch [regex]::Escape($required)) {
        Add-Failure "Launcher missing required startup intake: $required"
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
    foreach ($required in @("Get-ContinuumSummary", "IdleStale", "InteractivePromptBlocked", "LastPrompt", "ConsecutiveFailedSubmitAttempts", "LastApprovalChoice", "LastInteractivePromptBlock", "ChoiceReason", "ScanScope", "Watcher", "Target", "ReceiptParseFailures", "UsagePause", "UsagePaused", "LastResync", "codex_live_continue.resynced", "WatcherConsoleSelection", "ConsoleSelectionMode")) {
        if ($statusScript -notmatch [regex]::Escape($required)) {
            Add-Failure "Status script missing required behavior: $required"
        }
    }
}

foreach ($scriptName in @("start-continuum.ps1", "stop-continuum.ps1", "update-continuum.ps1")) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "scripts\$scriptName"))) {
        Add-Failure "Command script is missing: $scriptName"
    }
}

$repoText = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object {
        $_.FullName -notmatch "\\data\\" -and
        $_.FullName -notmatch "\\dist\\" -and
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
