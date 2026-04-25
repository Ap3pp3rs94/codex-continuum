$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-Matches {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw "$Message Missing pattern '$Pattern'."
    }
}

function Assert-NotMatches {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw "$Message Unexpected pattern '$Pattern'."
    }
}

Describe "Codex Continuum package" {
    It "has valid plugin metadata" {
        $manifest = Get-Content -LiteralPath (Join-Path $repoRoot ".codex-plugin\plugin.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $manifest.name -Expected "codex-continuum" -Message "Plugin name mismatch."
        Assert-Equal -Actual $manifest.license -Expected "MIT" -Message "Plugin license mismatch."
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
            Assert-Matches -Text $watcher -Pattern ([regex]::Escape($pattern)) -Message "Watcher behavior check failed."
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

        Assert-NotMatches -Text ($text -join "`n") -Pattern "FrancisLiveWindow" -Message "Old project-specific type name found."
    }
}
