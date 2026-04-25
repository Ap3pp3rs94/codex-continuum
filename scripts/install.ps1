[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$destinationRoot = Join-Path $CodexHome "plugins\codex-continuum"

if ($sourceRoot.TrimEnd("\") -ieq $destinationRoot.TrimEnd("\")) {
    Write-Host "Codex Continuum is already installed at $destinationRoot"
    return
}

if ($PSCmdlet.ShouldProcess($destinationRoot, "Install Codex Continuum")) {
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null

    Get-ChildItem -LiteralPath $sourceRoot -Force |
        Where-Object { $_.Name -notin @(".git", "data") } |
        Copy-Item -Destination $destinationRoot -Recurse -Force
}

Write-Host "Installed Codex Continuum to $destinationRoot"
