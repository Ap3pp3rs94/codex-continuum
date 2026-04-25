[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [string]$Version = "",

    [string]$Repository = "Ap3pp3rs94/codex-continuum",

    [string]$InstallRoot = "",

    [switch]$SkipValidation,

    [switch]$Force
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$currentRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = $currentRoot
}
else {
    $InstallRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
}

if ((Test-Path -LiteralPath (Join-Path $InstallRoot ".git")) -and -not $Force) {
    throw "InstallRoot appears to be a git checkout: $InstallRoot. Use git pull there, or pass -Force to overwrite from a release zip."
}

function Get-ReleaseMetadata {
    if ([string]::IsNullOrWhiteSpace($Version)) {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers @{ "User-Agent" = "codex-continuum-updater" }
    }

    $tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
    return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/tags/$tag" -Headers @{ "User-Agent" = "codex-continuum-updater" }
}

$release = Get-ReleaseMetadata
$releaseTag = [string]$release.tag_name
if ([string]::IsNullOrWhiteSpace($releaseTag)) {
    throw "Could not resolve a release tag for $Repository."
}

$releaseVersion = $releaseTag.TrimStart("v")
$zipName = "codex-continuum-plugin-v$releaseVersion.zip"
$hashName = "$zipName.sha256"
$zipAsset = @($release.assets | Where-Object { [string]$_.name -eq $zipName } | Select-Object -First 1)
$hashAsset = @($release.assets | Where-Object { [string]$_.name -eq $hashName } | Select-Object -First 1)

if ($zipAsset.Count -eq 0) {
    throw "Release $releaseTag does not contain $zipName."
}

if ($hashAsset.Count -eq 0) {
    throw "Release $releaseTag does not contain $hashName."
}

if ($WhatIfPreference) {
    return [pscustomobject]@{
        Version = $releaseVersion
        Tag = $releaseTag
        InstallRoot = $InstallRoot
        ZipAsset = [string]$zipAsset.browser_download_url
        HashAsset = [string]$hashAsset.browser_download_url
        Planned = $true
        Validated = $false
    }
}

$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-continuum-update-$PID"
$downloadRoot = Join-Path $workRoot "download"
$extractRoot = Join-Path $workRoot "extract"

if (Test-Path -LiteralPath $workRoot) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

try {
    $zipPath = Join-Path $downloadRoot $zipName
    $hashPath = Join-Path $downloadRoot $hashName

    Invoke-WebRequest -Uri ([string]$zipAsset.browser_download_url) -OutFile $zipPath
    Invoke-WebRequest -Uri ([string]$hashAsset.browser_download_url) -OutFile $hashPath

    $expectedHash = ((Get-Content -LiteralPath $hashPath -Raw).Trim() -split "\s+")[0]
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    if ($actualHash -ine $expectedHash) {
        throw "SHA256 mismatch for $zipName. Expected $expectedHash, got $actualHash."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $pluginRoot = Join-Path $extractRoot "codex-continuum"
    $manifestPath = Join-Path $pluginRoot ".codex-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Downloaded plugin zip is missing .codex-plugin\plugin.json."
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.name -ne "codex-continuum") {
        throw "Downloaded plugin manifest has unexpected name: $($manifest.name)"
    }

    if ([string]$manifest.version -ne $releaseVersion) {
        throw "Downloaded plugin version '$($manifest.version)' does not match release '$releaseVersion'."
    }

    if ($PSCmdlet.ShouldProcess($InstallRoot, "Update Codex Continuum to $releaseTag")) {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        Get-ChildItem -LiteralPath $pluginRoot -Force |
            Where-Object { $_.Name -ne "data" } |
            Copy-Item -Destination $InstallRoot -Recurse -Force

        if (-not $SkipValidation) {
            $validatePath = Join-Path $InstallRoot "scripts\validate.ps1"
            if (-not (Test-Path -LiteralPath $validatePath)) {
                throw "Updated install is missing validation script: $validatePath"
            }

            & powershell -NoProfile -ExecutionPolicy Bypass -File $validatePath
            if (-not $?) {
                throw "Updated install validation failed."
            }
        }
    }

    [pscustomobject]@{
        Version = $releaseVersion
        Tag = $releaseTag
        InstallRoot = $InstallRoot
        ZipSha256 = $actualHash
        Validated = [bool](-not $SkipValidation)
    }
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
