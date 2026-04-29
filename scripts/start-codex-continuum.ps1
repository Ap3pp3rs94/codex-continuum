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
    [string]$StatusPattern = "(?m)^\s*Working\s*$",

    [ValidateNotNullOrEmpty()]
    [string]$BackgroundWaitPattern = "(?m)^\s*Waiting for background(?:\s+\S.*)?\s*$",

    [string]$TitleWorkingPattern = "(^|:\s*)[\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f]\s+",

    [string]$UsageWarningPattern = "(?i)(\b(?:try again|resets?|reset|available|renews?)\s+(?:at|in|on)\b|\b(?:usage|rate|quota|message|token)\s+(?:limit|cap|quota)\s+(?:reached|exceeded)\b|\b(?:reached|exceeded|hit)\s+(?:your\s+)?(?:usage|rate|message|token|quota)\s+(?:limit|cap|quota)\b|\blimit\s+(?:reached|exceeded)\b)",

    [string]$ApprovalPromptPattern = "(?is)(permission|approval|approve|allow|grant|sandbox|trust|would you like to run|run the following command|yes,\s*proceed|tell codex what to do differently|never ask|don't ask|dont ask|\byes\b|\bno\b)",

    [string]$InteractivePromptBlockPattern = "(?ims)(would you like to|run the following command|yes,\s*proceed|do not ask again|don't ask again|dont ask again|tell codex what to do differently|^\s*[1-9][\.)]\s+\S)",

    [ValidatePattern("^[1-9]$")]
    [string]$ApprovalChoice = "1",

    [string]$DoNotAskAgainApprovalPattern = "(?is)(do not ask again|don't ask again|dont ask again|never ask again)",

    [ValidatePattern("^[1-9]$")]
    [string]$DoNotAskAgainApprovalChoice = "2",

    [ValidateRange(0, 3600)]
    [int]$ApprovalChoiceCooldownSeconds = 5,

    [ValidateRange(0, 604800)]
    [int]$UsagePauseFallbackSeconds = 3600,

    [ValidateRange(100, 10000)]
    [int]$PollMilliseconds = 750,

    [ValidateRange(100, 30000)]
    [int]$StableClearMilliseconds = 5000,

    [ValidateRange(500, 10000)]
    [int]$SubmitConfirmMilliseconds = 3500,

    [ValidateRange(0, 3600)]
    [int]$CooldownSeconds = 8,

    [ValidateRange(0, 1000000)]
    [int]$MaxPrompts = 0,

    [ValidateRange(0, 100)]
    [int]$MaxFailedSubmitAttempts = 3,

    [ValidateRange(0, 60)]
    [int]$AttachDelaySeconds = 0,

    [ValidateRange(0, 86400)]
    [int]$TimeoutSeconds = 0,

    [string]$ReceiptPath = "",

    [string]$KillFlagPath = "",

    [switch]$ProbeOnly,

    [switch]$ListCandidates,

    [switch]$AllowFullWindowFallback,

    [switch]$RequireObservedWorkingBeforeFirstPrompt,

    [switch]$VerboseStatusText,

    [switch]$PauseWhenTargetNotForeground,

    [switch]$AutoSelectApprovalChoice,

    [switch]$DisableUsageLimitPause,

    [switch]$NonInteractive
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

function Resolve-LiveCodexWindowCandidateFromProcessId {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,

        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    $candidateById = @{}
    foreach ($candidate in $Candidates) {
        $candidateById[[int]$candidate.ProcessId] = $candidate
    }

    $tree = Get-ProcessTreeByParent
    $parentById = @{}
    foreach ($row in $tree.Rows) {
        $parentById[[int]$row.ProcessId] = [int]$row.ParentProcessId
    }

    $visited = @{}
    $current = $ProcessId
    while ($current -gt 0 -and -not $visited.ContainsKey($current)) {
        $visited[$current] = $true
        if ($candidateById.ContainsKey($current)) {
            return $candidateById[$current]
        }

        if (-not $parentById.ContainsKey($current)) {
            break
        }

        $current = [int]$parentById[$current]
    }

    return $null
}

function Read-InteractiveTargetProcessId {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    if ($Candidates.Count -eq 0) {
        throw "No live Codex PowerShell windows found. Start Codex in a visible PowerShell window first."
    }

    Write-Host "Live Codex PowerShell windows:"
    Write-Host (Format-CandidateTable -Candidates $Candidates)

    while ($true) {
        $rawProcessId = (Read-Host "Target visible Codex PowerShell PID").Trim()
        $parsedProcessId = 0
        if (-not [int]::TryParse($rawProcessId, [ref]$parsedProcessId) -or $parsedProcessId -le 0) {
            Write-Warning "Enter a positive numeric PID from the candidate list."
            continue
        }

        $candidate = Resolve-LiveCodexWindowCandidateFromProcessId -ProcessId $parsedProcessId -Candidates $Candidates
        if ($null -eq $candidate) {
            Write-Warning "PID $parsedProcessId is not a live Codex PowerShell window or descendant. Choose one of the displayed target windows."
            continue
        }

        $resolvedProcessId = [int]$candidate.ProcessId
        if ($resolvedProcessId -ne $parsedProcessId) {
            Write-Host "Resolved PID $parsedProcessId to visible Codex PowerShell PID $resolvedProcessId ($($candidate.Title))."
        }

        return $resolvedProcessId
    }
}

function Read-InteractiveSessionId {
    while ($true) {
        $rawSessionId = (Read-Host "Session/thread id").Trim()
        if (-not [string]::IsNullOrWhiteSpace($rawSessionId)) {
            return $rawSessionId
        }

        Write-Warning "Session/thread id is required before Continuum starts."
    }
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

if (-not $NonInteractive) {
    $needsTargetPrompt = $TargetProcessId -eq 0 -and $TargetWindowHandle -eq 0
    $needsSessionPrompt = [string]::IsNullOrWhiteSpace($SessionId)

    if ($needsTargetPrompt -or $needsSessionPrompt) {
        $candidates = @(Get-LiveCodexWindowCandidate)

        if ($needsTargetPrompt) {
            $TargetProcessId = Read-InteractiveTargetProcessId -Candidates $candidates
        }

        if ($needsSessionPrompt) {
            $SessionId = Read-InteractiveSessionId
        }
    }
}

if ($TargetProcessId -gt 0 -and $TargetWindowHandle -eq 0) {
    $candidates = @(Get-LiveCodexWindowCandidate)
    $candidate = Resolve-LiveCodexWindowCandidateFromProcessId -ProcessId $TargetProcessId -Candidates $candidates
    if ($null -ne $candidate) {
        $resolvedProcessId = [int]$candidate.ProcessId
        if ($resolvedProcessId -ne $TargetProcessId) {
            Write-Host "Resolved PID $TargetProcessId to visible Codex PowerShell PID $resolvedProcessId ($($candidate.Title))."
            $TargetProcessId = $resolvedProcessId
        }
    }
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
    BackgroundWaitPattern = $BackgroundWaitPattern
    TitleWorkingPattern = $TitleWorkingPattern
    UsageWarningPattern = $UsageWarningPattern
    ApprovalPromptPattern = $ApprovalPromptPattern
    InteractivePromptBlockPattern = $InteractivePromptBlockPattern
    ApprovalChoice = $ApprovalChoice
    DoNotAskAgainApprovalPattern = $DoNotAskAgainApprovalPattern
    DoNotAskAgainApprovalChoice = $DoNotAskAgainApprovalChoice
    ApprovalChoiceCooldownSeconds = $ApprovalChoiceCooldownSeconds
    UsagePauseFallbackSeconds = $UsagePauseFallbackSeconds
    PollMilliseconds = $PollMilliseconds
    StableClearMilliseconds = $StableClearMilliseconds
    SubmitConfirmMilliseconds = $SubmitConfirmMilliseconds
    CooldownSeconds = $CooldownSeconds
    MaxPrompts = $MaxPrompts
    MaxFailedSubmitAttempts = $MaxFailedSubmitAttempts
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

if (-not [string]::IsNullOrWhiteSpace($KillFlagPath)) {
    $watcherParameters.KillFlagPath = $KillFlagPath
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

if ($AutoSelectApprovalChoice) {
    $watcherParameters.AutoSelectApprovalChoice = $true
}

if ($DisableUsageLimitPause) {
    $watcherParameters.DisableUsageLimitPause = $true
}

if ($WhatIfPreference) {
    $watcherParameters.WhatIf = $true
}

& $watcherPath @watcherParameters
