[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
param(
    [string]$SessionId = "",

    [Alias("Project")]
    [string]$ProjectName = "",

    [ValidateRange(0, 2147483647)]
    [int]$TargetProcessId = 0,

    [ValidateRange(0, [long]::MaxValue)]
    [long]$TargetWindowHandle = 0,

    [string]$WindowTitlePattern = "",

    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 256)]
    [string]$Prompt = "continue",

    [ValidateNotNullOrEmpty()]
    [string]$StatusPattern = "\bWorking\b",

    [string]$TitleWorkingPattern = "(^|:\s*)[\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f]\s+",

    [string]$UsageWarningPattern = "(?i)(usage limit|rate limit|limit reached|usage capped|quota|try again.*(?:at|in)|resets?\s+(?:at|in)|reset\s+(?:at|in|time))",

    [ValidateRange(0, 604800)]
    [int]$UsagePauseFallbackSeconds = 3600,

    [ValidateRange(100, 10000)]
    [int]$PollMilliseconds = 750,

    [ValidateRange(100, 30000)]
    [int]$StableClearMilliseconds = 1200,

    [ValidateRange(500, 10000)]
    [int]$SubmitConfirmMilliseconds = 3500,

    [ValidateRange(0, 3600)]
    [int]$CooldownSeconds = 8,

    [ValidateRange(0, 1000000)]
    [int]$MaxPrompts = 0,

    [ValidateRange(0, 60)]
    [int]$AttachDelaySeconds = 0,

    [ValidateRange(0, 86400)]
    [int]$TimeoutSeconds = 0,

    [string]$ReceiptPath = "",

    [switch]$ProbeOnly,

    [switch]$ListCandidates,

    [switch]$AllowFullWindowFallback,

    [switch]$RequireObservedWorkingBeforeFirstPrompt,

    [switch]$VerboseStatusText,

    [switch]$PauseWhenTargetNotForeground,

    [switch]$DisableUsageLimitPause
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "start-codex-continuum.ps1 only supports Windows live sessions."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcherPath = Join-Path $scriptRoot "codex-live-continue.ps1"
if (-not (Test-Path -LiteralPath $watcherPath)) {
    throw "Watcher script is missing: $watcherPath"
}

$effectiveWindowTitlePattern = $WindowTitlePattern
if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
    $projectPattern = [regex]::Escape($ProjectName)
    if ([string]::IsNullOrWhiteSpace($effectiveWindowTitlePattern)) {
        $effectiveWindowTitlePattern = $projectPattern
    }
    else {
        $effectiveWindowTitlePattern = "(?=.*$effectiveWindowTitlePattern)(?=.*$projectPattern)"
    }
}

function Get-ProcessTreeByParent {
    $rows = Get-CimInstance Win32_Process |
        Select-Object ProcessId, ParentProcessId, Name, CommandLine

    $children = @{}
    foreach ($row in $rows) {
        $parentId = [int]$row.ParentProcessId
        if (-not $children.ContainsKey($parentId)) {
            $children[$parentId] = New-Object System.Collections.ArrayList
        }
        [void]$children[$parentId].Add($row)
    }

    return @{
        Rows = $rows
        Children = $children
    }
}

function Test-HasCodexDescendant {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Children
    )

    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($ProcessId)

    while ($queue.Count -gt 0) {
        $current = [int]$queue.Dequeue()
        if (-not $Children.ContainsKey($current)) {
            continue
        }

        foreach ($child in $Children[$current]) {
            $name = [string]$child.Name
            $commandLine = [string]$child.CommandLine
            if (
                ($name -ieq "node.exe" -and $commandLine -match "@openai[\\/]+codex[\\/]+bin[\\/]+codex\.js") -or
                ($name -ieq "codex.exe" -and $commandLine -match "@openai[\\/]+codex")
            ) {
                return $true
            }

            $queue.Enqueue([int]$child.ProcessId)
        }
    }

    return $false
}

function Get-LiveCodexWindowCandidate {
    $tree = Get-ProcessTreeByParent
    $candidates = New-Object System.Collections.ArrayList

    foreach ($row in $tree.Rows) {
        $name = [string]$row.Name
        if ($name -notin @("pwsh.exe", "powershell.exe", "WindowsTerminal.exe")) {
            continue
        }

        if (-not (Test-HasCodexDescendant -ProcessId ([int]$row.ProcessId) -Children $tree.Children)) {
            continue
        }

        $process = Get-Process -Id ([int]$row.ProcessId) -ErrorAction SilentlyContinue
        if ($null -eq $process -or $process.MainWindowHandle -eq 0) {
            continue
        }

        $title = [string]$process.MainWindowTitle
        if ($effectiveWindowTitlePattern -and $title -notmatch $effectiveWindowTitlePattern) {
            continue
        }

        [void]$candidates.Add([pscustomobject]@{
            ProcessId = [int]$process.Id
            ProcessName = [string]$process.ProcessName
            Title = $title
            Handle = ("0x{0:x}" -f ([int64]$process.MainWindowHandle))
        })
    }

    return @($candidates)
}

function Format-CandidateTable {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    $Candidates |
        Sort-Object ProcessId |
        Format-Table -AutoSize ProcessId, ProcessName, Handle, Title |
        Out-String
}

if ($ListCandidates) {
    $candidates = @(Get-LiveCodexWindowCandidate)
    if ($candidates.Count -eq 0) {
        Write-Host "No live Codex PowerShell windows found."
        return
    }

    Write-Host (Format-CandidateTable -Candidates $candidates)
    return
}

if ($TargetProcessId -eq 0 -and $TargetWindowHandle -eq 0) {
    $candidates = @(Get-LiveCodexWindowCandidate)
    if ($candidates.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
            throw "No live Codex PowerShell window found for project '$ProjectName'. Pass -ListCandidates, -TargetProcessId, or -TargetWindowHandle."
        }

        throw "No live Codex PowerShell window found. Pass -ProjectName, -TargetProcessId, or -TargetWindowHandle."
    }

    if ($candidates.Count -gt 1) {
        Write-Host "Multiple live Codex PowerShell windows found:"
        Write-Host (Format-CandidateTable -Candidates $candidates)
        throw "Pass -ProjectName, -TargetProcessId, or -TargetWindowHandle for the exact live Codex session."
    }

    $TargetProcessId = [int]$candidates[0].ProcessId
    Write-Host "Selected live Codex PowerShell PID $TargetProcessId ($($candidates[0].Title))."
}

$watcherParameters = @{
    Prompt = $Prompt
    StatusPattern = $StatusPattern
    TitleWorkingPattern = $TitleWorkingPattern
    UsageWarningPattern = $UsageWarningPattern
    UsagePauseFallbackSeconds = $UsagePauseFallbackSeconds
    PollMilliseconds = $PollMilliseconds
    StableClearMilliseconds = $StableClearMilliseconds
    SubmitConfirmMilliseconds = $SubmitConfirmMilliseconds
    CooldownSeconds = $CooldownSeconds
    MaxPrompts = $MaxPrompts
    AttachDelaySeconds = $AttachDelaySeconds
    TimeoutSeconds = $TimeoutSeconds
}

if ($TargetProcessId -gt 0) {
    $watcherParameters.TargetProcessId = $TargetProcessId
}

if ($TargetWindowHandle -gt 0) {
    $watcherParameters.TargetWindowHandle = $TargetWindowHandle
}

if (-not [string]::IsNullOrWhiteSpace($effectiveWindowTitlePattern)) {
    $watcherParameters.WindowTitlePattern = $effectiveWindowTitlePattern
}

if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $watcherParameters.SessionId = $SessionId
}

if (-not [string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $watcherParameters.ReceiptPath = $ReceiptPath
}

if ($ProbeOnly) {
    $watcherParameters.ProbeOnly = $true
}

if ($AllowFullWindowFallback) {
    $watcherParameters.AllowFullWindowFallback = $true
}

if ($RequireObservedWorkingBeforeFirstPrompt) {
    $watcherParameters.RequireObservedWorkingBeforeFirstPrompt = $true
}

if ($VerboseStatusText) {
    $watcherParameters.VerboseStatusText = $true
}

if ($PauseWhenTargetNotForeground) {
    $watcherParameters.PauseWhenTargetNotForeground = $true
}

if ($DisableUsageLimitPause) {
    $watcherParameters.DisableUsageLimitPause = $true
}

if ($WhatIfPreference) {
    $watcherParameters.WhatIf = $true
}

& $watcherPath @watcherParameters
