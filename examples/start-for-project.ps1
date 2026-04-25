param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [string]$SessionId = ""
)

$continuum = Join-Path $env:USERPROFILE ".codex\plugins\codex-continuum\codex-continuum.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File $continuum `
    -ProjectName $ProjectName `
    -SessionId $SessionId
