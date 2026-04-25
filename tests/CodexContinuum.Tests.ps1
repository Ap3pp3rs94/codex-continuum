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
            "confirmed_work_observed",
            "send_confirmation",
            "RequireObservedWorkingBeforeFirstPrompt",
            'observedWorking = -not',
            "UsageWarningPattern",
            "UsagePauseFallbackSeconds",
            "Get-UsagePauseState",
            "codex_live_continue.usage_paused",
            "codex_live_continue.usage_resumed"
        )) {
            if ($watcher -notmatch [regex]::Escape($pattern)) {
                throw "Watcher behavior check failed. Missing pattern '$pattern'."
            }
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
                input_method = "test-confirmed-title"
                confirmed_work_observed = $true
                error = ""
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
