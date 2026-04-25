[CmdletBinding()]
param(
    [string]$Version = "",

    [string]$OutputDirectory = "",

    [switch]$Force
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestPath = Join-Path $repoRoot ".codex-plugin\plugin.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$versionProvided = -not [string]::IsNullOrWhiteSpace($Version)

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string]$manifest.version
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "Package version is empty."
}

if ($versionProvided -and $Version -ne [string]$manifest.version) {
    throw "Package version '$Version' does not match plugin manifest version '$($manifest.version)'."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "dist"
}
else {
    $OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
}

$pluginName = [string]$manifest.name
$packageName = "$pluginName-plugin-v$Version"
$zipPath = Join-Path $OutputDirectory "$packageName.zip"
$hashPath = "$zipPath.sha256"

if ((Test-Path -LiteralPath $zipPath) -and -not $Force) {
    throw "Package already exists: $zipPath. Pass -Force to overwrite."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "$packageName-$PID"
$stagingPluginRoot = Join-Path $stagingRoot $pluginName
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stagingPluginRoot -Force | Out-Null

$includeItems = @(
    ".codex-plugin",
    "docs",
    "examples",
    "scripts",
    "tests",
    "codex-continuum.ps1",
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "ROADMAP.md",
    "SECURITY.md"
)

foreach ($item in $includeItems) {
    $source = Join-Path $repoRoot $item
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Package source item is missing: $item"
    }

    Copy-Item -LiteralPath $source -Destination $stagingPluginRoot -Recurse -Force
}

$packageManifest = [ordered]@{
    name = $pluginName
    version = $Version
    repository = [string]$manifest.repository
    packaged_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    install_root = "%USERPROFILE%\.codex\plugins\$pluginName"
    entrypoint = ".\codex-continuum.ps1"
}

$packageManifest |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $stagingPluginRoot "PACKAGE-MANIFEST.json") -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

if (Test-Path -LiteralPath $hashPath) {
    Remove-Item -LiteralPath $hashPath -Force
}

Compress-Archive -LiteralPath $stagingPluginRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
"$($hash.Hash)  $(Split-Path -Leaf $zipPath)" | Set-Content -LiteralPath $hashPath -Encoding ASCII

Remove-Item -LiteralPath $stagingRoot -Recurse -Force

Write-Host "Packaged Codex Continuum plugin:"
Write-Host $zipPath
Write-Host "SHA256:"
Write-Host $hash.Hash

return [pscustomobject]@{
    Name = $packageName
    Version = $Version
    ZipPath = $zipPath
    Sha256Path = $hashPath
    Sha256 = $hash.Hash
}
