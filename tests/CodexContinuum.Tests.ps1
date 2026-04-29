$repoRoot = Split-Path -Parent $PSScriptRoot

Describe "Codex Continuum package" {
    It "has valid plugin metadata" {
        $manifest = Get-Content -LiteralPath (Join-Path $repoRoot ".codex-plugin\plugin.json") -Raw | ConvertFrom-Json
        if ($manifest.name -ne "codex-continuum") {
            throw "Plugin name mismatch. Expected 'codex-continuum', got '$($manifest.name)'."
        }

        if ($manifest.license -ne "MIT") {
            throw "Plugin license mismatch. Expected 'MIT', got '$($manifest.license)'."
        }
    }

    It "keeps the confirmed submit fallback in the watcher" {
        $watcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\codex-live-continue.ps1") -Raw
        foreach ($pattern in @(
            "SubmitConfirmMilliseconds",
            'StableClearMilliseconds = 5000',
            "sendkeys-tilde",
            "sendkeys-ctrl-m",
            "SendEnterKey",
            "SendEscapeKey",
            "-confirmed",
            "TitleWorkingPattern",
            "WorkingSignal",
            "ForceForegroundWindow",
            "Set-LiveSessionForeground",
            "prompt_attempts",
            "MaxFailedSubmitAttempts",
            "consecutive_failed_submit_attempts",
            "repeated_failed_submit",
            "KillFlagPath",
            "kill_flag",
            "confirmed_work_observed",
            "send_confirmation",
            "RequireObservedWorkingBeforeFirstPrompt",
            'observedWorking = -not',
            '[string]$StatusPattern = "(?m)^\s*Working\s*$"',
            '[string]$BackgroundWaitPattern = "(?m)^\s*Waiting for background',
            "-cmatch `$StatusPattern",
            "-cmatch `$BackgroundWaitPattern",
            "background_wait",
            "Clear-ConsoleSelectionMode",
            "codex_live_continue.selection_mode_cleared",
            "UsageWarningPattern",
            "UsagePauseFallbackSeconds",
            "Get-UsagePauseState",
            "Test-ActionableUsageWarningContext",
            "codex_live_continue.usage_paused",
            "codex_live_continue.usage_resumed",
            "AutoSelectApprovalChoice",
            "ApprovalPromptPattern",
            "InteractivePromptBlockPattern",
            "would you like to run",
            "DoNotAskAgainApprovalPattern",
            "DoNotAskAgainApprovalChoice",
            "FullWindow",
            "full_window_tail",
            "not_scanned_working",
            "Get-ApprovalPromptMatch",
            "Get-InteractivePromptBlock",
            "Send-ApprovalChoice",
            "codex_live_continue.approval_choice",
            "codex_live_continue.interactive_prompt_blocked"
        )) {
            if ($watcher -notmatch [regex]::Escape($pattern)) {
                throw "Watcher behavior check failed. Missing pattern '$pattern'."
            }
        }

        if ($watcher -match '\$titleLooksInteractive') {
            throw "Watcher still treats a Select title alone as an interactive prompt."
        }

        $defaultUsagePatternMatch = [regex]::Match($watcher, '\[string\]\$UsageWarningPattern = "([^"]+)"')
        if (-not $defaultUsagePatternMatch.Success) {
            throw "Could not find the default usage warning pattern."
        }

        $defaultUsagePattern = $defaultUsagePatternMatch.Groups[1].Value
        if ("docs\canonical\ROADMAP.md:24193:* quota exhaustion behavior" -match $defaultUsagePattern) {
            throw "Default usage warning pattern matches generic quota documentation text."
        }

        if ("Usage limit reached. Try again in 30 minutes." -notmatch $defaultUsagePattern) {
            throw "Default usage warning pattern does not match an actionable usage-limit warning."
        }
    }

    It "keeps the downloadable plugin packager" {
        $packager = Join-Path $repoRoot "scripts\package-plugin.ps1"
        if (-not (Test-Path -LiteralPath $packager)) {
            throw "Package script is missing."
        }

        $packagerText = Get-Content -LiteralPath $packager -Raw
        foreach ($pattern in @("Compress-Archive", "PACKAGE-MANIFEST.json", ".codex-plugin", "SHA256")) {
            if ($packagerText -notmatch [regex]::Escape($pattern)) {
                throw "Package script missing pattern '$pattern'."
            }
        }
    }

    It "keeps the command wrapper surface" {
        $entrypoint = Get-Content -LiteralPath (Join-Path $repoRoot "codex-continuum.ps1") -Raw
        foreach ($pattern in @(
            "scripts\start-continuum.ps1",
            "scripts\stop-continuum.ps1",
            "scripts\get-continuum-status.ps1",
            "scripts\update-continuum.ps1"
        )) {
            if ($entrypoint -notmatch [regex]::Escape($pattern)) {
                throw "Entrypoint missing command route '$pattern'."
            }
        }

        $stopScript = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\stop-continuum.ps1") -Raw
        foreach ($pattern in @("Stop-Process", "codex_live_continue.stop_requested", "TargetProcessId", "SessionId")) {
            if ($stopScript -notmatch [regex]::Escape($pattern)) {
                throw "Stop command missing pattern '$pattern'."
            }
        }

        $updateScript = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\update-continuum.ps1") -Raw
        foreach ($pattern in @("Invoke-WebRequest", "SHA256", "Expand-Archive", ".git", "Validate")) {
            if ($updateScript -notmatch [regex]::Escape($pattern)) {
                throw "Update command missing pattern '$pattern'."
            }
        }
    }

    It "keeps the explicit startup intake before attaching" {
        $launcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\start-codex-continuum.ps1") -Raw
        foreach ($pattern in @(
            "Read-InteractiveTargetProcessId",
            "Read-InteractiveSessionId",
            "Resolve-LiveCodexWindowCandidateFromProcessId",
            "Target visible Codex PowerShell PID",
            "Session/thread id",
            "NonInteractive",
            "MaxFailedSubmitAttempts",
            "KillFlagPath",
            "AutoSelectApprovalChoice",
            "ApprovalChoice",
            "DoNotAskAgainApprovalChoice",
            "ApprovalPromptPattern",
            "InteractivePromptBlockPattern"
        )) {
            if ($launcher -notmatch [regex]::Escape($pattern)) {
                throw "Launcher startup intake missing pattern '$pattern'."
            }
        }
    }

    It "summarizes Continuum status from receipts" {
        $statusScript = Join-Path $repoRoot "scripts\get-continuum-status.ps1"
        if (-not (Test-Path -LiteralPath $statusScript)) {
            throw "Status script is missing."
        }

        $entrypoint = Get-Content -LiteralPath (Join-Path $repoRoot "codex-continuum.ps1") -Raw
        if ($entrypoint -notmatch "get-continuum-status\.ps1") {
            throw "Entrypoint does not route to the status script."
        }

        $receipt = Join-Path ([System.IO.Path]::GetTempPath()) "codex-continuum-status-test-$PID.jsonl"
        $now = [DateTimeOffset]::Now
        @(
            ([ordered]@{
                ts = $now.AddSeconds(-10).ToString("o")
                event = "codex_live_continue.attached"
                target_process_id = $PID
                session_id = "test-session"
                handle = "0x1"
                title_working_pattern = "(^|:\s*)[\u280b]\s+"
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddSeconds(-4).ToString("o")
                event = "codex_live_continue.status"
                working = $true
                working_signal = "title"
                title = "Test"
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddSeconds(-2).ToString("o")
                event = "codex_live_continue.prompt"
                sent = $true
                prompt_count = 1
                prompt_attempts = 1
                consecutive_failed_submit_attempts = 1
                input_method = "test-confirmed-title"
                confirmed_work_observed = $true
                error = ""
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddSeconds(-1).ToString("o")
                event = "codex_live_continue.approval_choice"
                sent = $true
                choice = "2"
                choice_reason = "do_not_ask_again"
                scan_scope = "full_window_tail"
                approval_choice_count = 2
                approval_choice_attempts = 2
                input_method = "test-choice"
                error = ""
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddMilliseconds(-500).ToString("o")
                event = "codex_live_continue.interactive_prompt_blocked"
                block_reason = "command_prompt"
                scan_scope = "full_window_tail"
                prompt_block_count = 1
                title = "Select Test"
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddMilliseconds(-250).ToString("o")
                event = "codex_live_continue.attached"
                target_process_id = 0
                session_id = "test-session"
                handle = "0x1"
                title_working_pattern = "(^|:\s*)[\u280b]\s+"
            } | ConvertTo-Json -Compress)
        ) | Set-Content -LiteralPath $receipt -Encoding UTF8

        try {
            $json = & $statusScript -ReceiptPath $receipt -Json
            $summary = ($json | Out-String) | ConvertFrom-Json
            if ($summary.ReceiptExists -ne $true) {
                throw "Status did not report receipt existence."
            }

            if ($summary.Session.Id -ne "test-session") {
                throw "Status did not report the session id."
            }

            if ($summary.LastPrompt.PromptCount -ne 1) {
                throw "Status did not report prompt count."
            }

            if ($summary.LastPrompt.ConsecutiveFailedSubmitAttempts -ne 1) {
                throw "Status did not report failed submit attempts."
            }

            if ($summary.LastApprovalChoice.Choice -ne "2") {
                throw "Status did not report approval choice."
            }

            if ($summary.LastApprovalChoice.ChoiceReason -ne "do_not_ask_again") {
                throw "Status did not report approval choice reason."
            }

            if ($summary.LastApprovalChoice.ScanScope -ne "full_window_tail") {
                throw "Status did not report approval scan scope."
            }

            if ($summary.LastInteractivePromptBlock.Reason -ne "command_prompt") {
                throw "Status did not report interactive prompt block reason."
            }

            if ($summary.LastInteractivePromptBlock.ScanScope -ne "full_window_tail") {
                throw "Status did not report interactive prompt block scan scope."
            }

            if ($summary.LastInteractivePromptBlock.Active -ne $false) {
                throw "Status kept an interactive prompt block active after a newer attach."
            }
        }
        finally {
            Remove-Item -LiteralPath $receipt -Force -ErrorAction SilentlyContinue
        }
    }

    It "reports usage-limit pause receipts" {
        $statusScript = Join-Path $repoRoot "scripts\get-continuum-status.ps1"
        $receipt = Join-Path ([System.IO.Path]::GetTempPath()) "codex-continuum-usage-pause-test-$PID.jsonl"
        $now = [DateTimeOffset]::Now
        $pauseUntil = $now.AddMinutes(30)
        @(
            ([ordered]@{
                ts = $now.AddSeconds(-20).ToString("o")
                event = "codex_live_continue.attached"
                target_process_id = 0
                session_id = "usage-test-session"
                handle = "0x1"
                title_working_pattern = "(^|:\s*)[\u280b]\s+"
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddSeconds(-10).ToString("o")
                event = "codex_live_continue.usage_paused"
                pause_until = $pauseUntil.ToString("o")
                reason = "relative_reset_time"
                matched_text = "Usage limit reached. Try again in 30 minutes."
                fallback_used = $false
                prompts_sent = 2
                session_id = "usage-test-session"
            } | ConvertTo-Json -Compress)
        ) | Set-Content -LiteralPath $receipt -Encoding UTF8

        try {
            $json = & $statusScript -ReceiptPath $receipt -Json
            $summary = ($json | Out-String) | ConvertFrom-Json
            if ($summary.UsagePause.Active -ne $true) {
                throw "Status did not report active usage pause."
            }

            if ($summary.UsagePause.Reason -ne "relative_reset_time") {
                throw "Status did not report usage pause reason."
            }

            if ($summary.UsagePause.RemainingSeconds -le 0) {
                throw "Status did not report usage pause remaining time."
            }
        }
        finally {
            Remove-Item -LiteralPath $receipt -Force -ErrorAction SilentlyContinue
        }
    }

    It "clears usage-limit pause state after a newer attach" {
        $statusScript = Join-Path $repoRoot "scripts\get-continuum-status.ps1"
        $receipt = Join-Path ([System.IO.Path]::GetTempPath()) "codex-continuum-usage-pause-attach-test-$PID.jsonl"
        $now = [DateTimeOffset]::Now
        $pauseUntil = $now.AddMinutes(30)
        @(
            ([ordered]@{
                ts = $now.AddSeconds(-20).ToString("o")
                event = "codex_live_continue.usage_paused"
                pause_until = $pauseUntil.ToString("o")
                reason = "relative_reset_time"
                matched_text = "Usage limit reached. Try again in 30 minutes."
                fallback_used = $false
                prompts_sent = 2
                session_id = "usage-test-session"
            } | ConvertTo-Json -Compress),
            ([ordered]@{
                ts = $now.AddSeconds(-10).ToString("o")
                event = "codex_live_continue.attached"
                target_process_id = 0
                session_id = "usage-test-session"
                handle = "0x1"
                title_working_pattern = "(^|:\s*)[\u280b]\s+"
            } | ConvertTo-Json -Compress)
        ) | Set-Content -LiteralPath $receipt -Encoding UTF8

        try {
            $json = & $statusScript -ReceiptPath $receipt -Json
            $summary = ($json | Out-String) | ConvertFrom-Json
            if ($summary.UsagePause.Active -ne $false) {
                throw "Status kept a usage pause active after a newer attach."
            }
        }
        finally {
            Remove-Item -LiteralPath $receipt -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not keep the old project-specific type name" {
        $text = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch "\\data\\" -and
                $_.FullName -notmatch "\\dist\\" -and
                $_.FullName -notmatch "\\tests\\" -and
                $_.FullName -notmatch "\\scripts\\validate\.ps1$"
            } |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }

        if (($text -join "`n") -match "FrancisLiveWindow") {
            throw "Old project-specific type name found."
        }
    }
}
