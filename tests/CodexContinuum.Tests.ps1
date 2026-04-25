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
            "RequireObservedWorkingBeforeFirstPrompt",
            'observedWorking = -not'
        )) {
            if ($watcher -notmatch [regex]::Escape($pattern)) {
                throw "Watcher behavior check failed. Missing pattern '$pattern'."
            }
        }
    }

    It "does not keep the old project-specific type name" {
        $text = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch "\\data\\" -and
                $_.FullName -notmatch "\\tests\\" -and
                $_.FullName -notmatch "\\scripts\\validate\.ps1$"
            } |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }

        if (($text -join "`n") -match "FrancisLiveWindow") {
            throw "Old project-specific type name found."
        }
    }
}
