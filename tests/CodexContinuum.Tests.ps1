$repoRoot = Split-Path -Parent $PSScriptRoot

Describe "Codex Continuum package" {
    It "has valid plugin metadata" {
        $manifest = Get-Content -LiteralPath (Join-Path $repoRoot ".codex-plugin\plugin.json") -Raw | ConvertFrom-Json
        $manifest.name | Should Be "codex-continuum"
        $manifest.license | Should Be "MIT"
    }

    It "keeps the confirmed submit fallback in the watcher" {
        $watcher = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\codex-live-continue.ps1") -Raw
        $watcher | Should Match "SubmitConfirmMilliseconds"
        $watcher | Should Match "sendkeys-tilde"
        $watcher | Should Match "sendkeys-ctrl-m"
        $watcher | Should Match "SendEnterKey"
        $watcher | Should Match "-confirmed"
    }

    It "does not keep the old project-specific type name" {
        $text = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch "\\data\\" -and
                $_.FullName -notmatch "\\tests\\" -and
                $_.FullName -notmatch "\\scripts\\validate\.ps1$"
            } |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }

        ($text -join "`n") | Should Not Match "FrancisLiveWindow"
    }
}
