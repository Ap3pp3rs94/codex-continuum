[CmdletBinding()]
param(
    [string]$ReceiptPath = "",

    [ValidateRange(1, 100000)]
    [int]$Tail = 5000,

    [ValidateRange(1, 86400)]
    [int]$StaleSeconds = 30,

    [switch]$Json,

    [switch]$Watch,

    [ValidateRange(1, 3600)]
    [int]$RefreshSeconds = 5
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $ReceiptPath = Join-Path $repoRoot "data\operator\codex-live-continue.jsonl"
}
else {
    $ReceiptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReceiptPath)
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}

function Convert-ReceiptTime {
    param([object]$Event)

    $raw = [string](Get-PropertyValue -Object $Event -Name "ts" -Default "")
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    try {
        return [DateTimeOffset]::Parse($raw)
    }
    catch {
        return $null
    }
}

function Convert-ReceiptFieldTime {
    param(
        [object]$Event,
        [string]$Name
    )

    $raw = [string](Get-PropertyValue -Object $Event -Name $Name -Default "")
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    try {
        return [DateTimeOffset]::Parse($raw)
    }
    catch {
        return $null
    }
}

function Get-AgeSeconds {
    param([object]$Time)

    if ($null -eq $Time) {
        return $null
    }

    return [int][Math]::Max(0, [Math]::Round(([DateTimeOffset]::Now - $Time).TotalSeconds))
}

function Get-RemainingSeconds {
    param([object]$Time)

    if ($null -eq $Time) {
        return $null
    }

    return [int][Math]::Max(0, [Math]::Ceiling(($Time - [DateTimeOffset]::Now).TotalSeconds))
}

function Select-LastReceiptEvent {
    param(
        [object[]]$Events,
        [string]$Name
    )

    $matches = @($Events | Where-Object { [string](Get-PropertyValue -Object $_ -Name "event" -Default "") -eq $Name })
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[$matches.Count - 1]
}

function Convert-ToBoolean {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $text = [string]$Value
    return $text -ieq "true"
}

function Get-ContinuumWatcherProcess {
    $pattern = "(?i)-File\s+.*(codex-continuum|codex-live-continue|start-codex-continuum)\.ps1"
    $statusPattern = "(?i)(get-continuum-status\.ps1|(?:^|\s)(?:status|get-status|--status|-Status)(?:\s|$))"
    return @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                [int]$_.ProcessId -ne $PID -and
                $commandLine -match $pattern -and
                $commandLine -notmatch $statusPattern
            } |
            Select-Object ProcessId, ParentProcessId, Name, CommandLine
    )
}

function Get-ContinuumSummary {
    $receiptExists = Test-Path -LiteralPath $ReceiptPath
    $events = New-Object System.Collections.ArrayList
    $parseFailures = 0

    if ($receiptExists) {
        $lines = @(Get-Content -LiteralPath $ReceiptPath -Tail $Tail -ErrorAction Stop)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                [void]$events.Add(($line | ConvertFrom-Json))
            }
            catch {
                $parseFailures += 1
            }
        }
    }

    $eventArray = @($events)
    $lastEvent = if ($eventArray.Count -gt 0) { $eventArray[$eventArray.Count - 1] } else { $null }
    $lastAttached = Select-LastReceiptEvent -Events $eventArray -Name "codex_live_continue.attached"
    $lastStatus = Select-LastReceiptEvent -Events $eventArray -Name "codex_live_continue.status"
    $lastPrompt = Select-LastReceiptEvent -Events $eventArray -Name "codex_live_continue.prompt"
    $lastStopped = Select-LastReceiptEvent -Events $eventArray -Name "codex_live_continue.stopped"
    $lastUsagePaused = Select-LastReceiptEvent -Events $eventArray -Name "codex_live_continue.usage_paused"
    $lastUsageResumed = Select-LastReceiptEvent -Events $eventArray -Name "codex_live_continue.usage_resumed"

    $lastEventTime = Convert-ReceiptTime -Event $lastEvent
    $lastAttachedTime = Convert-ReceiptTime -Event $lastAttached
    $lastStatusTime = Convert-ReceiptTime -Event $lastStatus
    $lastPromptTime = Convert-ReceiptTime -Event $lastPrompt
    $lastStoppedTime = Convert-ReceiptTime -Event $lastStopped
    $lastUsagePausedTime = Convert-ReceiptTime -Event $lastUsagePaused
    $lastUsageResumedTime = Convert-ReceiptTime -Event $lastUsageResumed
    $usagePauseUntil = Convert-ReceiptFieldTime -Event $lastUsagePaused -Name "pause_until"

    $targetProcessId = [int](Get-PropertyValue -Object $lastAttached -Name "target_process_id" -Default 0)
    $targetProcess = $null
    if ($targetProcessId -gt 0) {
        $targetProcess = Get-Process -Id $targetProcessId -ErrorAction SilentlyContinue
    }

    $targetTitle = ""
    $targetHandle = 0
    if ($null -ne $targetProcess) {
        $targetTitle = [string]$targetProcess.MainWindowTitle
        $targetHandle = [int64]$targetProcess.MainWindowHandle
    }

    $titlePattern = [string](Get-PropertyValue -Object $lastAttached -Name "title_working_pattern" -Default "")
    $liveWorkingByTitle = $false
    if (-not [string]::IsNullOrWhiteSpace($titlePattern) -and -not [string]::IsNullOrWhiteSpace($targetTitle)) {
        $liveWorkingByTitle = $targetTitle -match $titlePattern
    }

    $watchers = @(Get-ContinuumWatcherProcess)
    $lastStatusWorking = Convert-ToBoolean (Get-PropertyValue -Object $lastStatus -Name "working" -Default $false)
    $liveTitleKnown = ($null -ne $targetProcess -and -not [string]::IsNullOrWhiteSpace($targetTitle))
    $currentWorking = $liveWorkingByTitle -or ((-not $liveTitleKnown) -and $lastStatusWorking)
    $lastPromptSent = Convert-ToBoolean (Get-PropertyValue -Object $lastPrompt -Name "sent" -Default $false)
    $lastPromptError = [string](Get-PropertyValue -Object $lastPrompt -Name "error" -Default "")
    $lastStatusSignal = [string](Get-PropertyValue -Object $lastStatus -Name "working_signal" -Default "")
    $lastStoppedReason = [string](Get-PropertyValue -Object $lastStopped -Name "reason" -Default "")
    $stoppedAfterAttach = $false
    if ($null -ne $lastStoppedTime -and $null -ne $lastAttachedTime) {
        $stoppedAfterAttach = $lastStoppedTime -gt $lastAttachedTime
    }

    $usagePauseActive = $false
    if ($null -ne $lastUsagePausedTime -and $null -ne $usagePauseUntil) {
        $usagePauseActive = $usagePauseUntil -gt [DateTimeOffset]::Now
        if ($null -ne $lastUsageResumedTime -and $lastUsageResumedTime -gt $lastUsagePausedTime) {
            $usagePauseActive = $false
        }

        if ($null -ne $lastStoppedTime -and $lastStoppedTime -gt $lastUsagePausedTime) {
            $usagePauseActive = $false
        }
    }

    $idleAge = $null
    if ($null -ne $lastStatusTime -and -not $currentWorking) {
        $idleAge = Get-AgeSeconds -Time $lastStatusTime
    }

    $state = "Unknown"
    $health = "Unknown"
    $action = "Inspect receipts."

    if (-not $receiptExists) {
        $state = "NoReceipts"
        $health = "Attention"
        $action = "Start Continuum or pass -ReceiptPath."
    }
    elseif ($eventArray.Count -eq 0) {
        $state = "NoReadableReceipts"
        $health = "Attention"
        $action = "Check receipt parsing and file permissions."
    }
    elseif ($stoppedAfterAttach) {
        $state = "Stopped"
        $health = "Attention"
        $action = "Restart Continuum."
    }
    elseif ($watchers.Count -eq 0) {
        $state = "NoWatcherProcess"
        $health = "Attention"
        $action = "Start Continuum."
    }
    elseif ($targetProcessId -gt 0 -and $null -eq $targetProcess) {
        $state = "TargetMissing"
        $health = "Attention"
        $action = "Restart Continuum against a live Codex window."
    }
    elseif ($usagePauseActive) {
        $state = "UsagePaused"
        $health = "Paused"
        $action = "Waiting for Codex usage reset before sending more continuation prompts."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($lastPromptError) -and -not $liveWorkingByTitle -and -not $lastStatusWorking) {
        $state = "LastPromptFailed"
        $health = "Attention"
        $action = "Inspect input_method and foreground focus."
    }
    elseif ($currentWorking) {
        $state = "Working"
        $health = "Healthy"
        $action = "Watching for completion."
    }
    elseif ($null -ne $idleAge -and $idleAge -ge $StaleSeconds) {
        $state = "IdleStale"
        $health = "Attention"
        $action = "Continuum should have sent a prompt; inspect watcher window and receipts."
    }
    else {
        $state = "Idle"
        $health = "Healthy"
        $action = "Waiting for stable idle/cooldown or next working transition."
    }

    return [pscustomobject]@{
        Health = $health
        State = $state
        Action = $action
        ReceiptPath = $ReceiptPath
        ReceiptExists = [bool]$receiptExists
        ReceiptEventsRead = [int]$eventArray.Count
        ReceiptParseFailures = [int]$parseFailures
        LastEvent = [pscustomobject]@{
            Event = [string](Get-PropertyValue -Object $lastEvent -Name "event" -Default "")
            At = if ($null -eq $lastEventTime) { $null } else { $lastEventTime.ToString("o") }
            AgeSeconds = Get-AgeSeconds -Time $lastEventTime
        }
        Watcher = [pscustomobject]@{
            Running = [bool]($watchers.Count -gt 0)
            ProcessIds = @($watchers | ForEach-Object { [int]$_.ProcessId })
            Count = [int]$watchers.Count
        }
        Target = [pscustomobject]@{
            ProcessId = $targetProcessId
            Running = [bool]($null -ne $targetProcess)
            MainWindowTitle = $targetTitle
            MainWindowHandle = $targetHandle
            LiveWorkingByTitle = [bool]$liveWorkingByTitle
            TitleWorkingPattern = $titlePattern
        }
        Session = [pscustomobject]@{
            Id = [string](Get-PropertyValue -Object $lastAttached -Name "session_id" -Default "")
            Handle = [string](Get-PropertyValue -Object $lastAttached -Name "handle" -Default "")
            AttachedAt = if ($null -eq $lastAttachedTime) { $null } else { $lastAttachedTime.ToString("o") }
        }
        LastStatus = [pscustomobject]@{
            At = if ($null -eq $lastStatusTime) { $null } else { $lastStatusTime.ToString("o") }
            AgeSeconds = Get-AgeSeconds -Time $lastStatusTime
            Working = [bool]$lastStatusWorking
            WorkingSignal = $lastStatusSignal
            Title = [string](Get-PropertyValue -Object $lastStatus -Name "title" -Default "")
            IdleAgeSeconds = $idleAge
        }
        LastPrompt = [pscustomobject]@{
            At = if ($null -eq $lastPromptTime) { $null } else { $lastPromptTime.ToString("o") }
            AgeSeconds = Get-AgeSeconds -Time $lastPromptTime
            Sent = [bool]$lastPromptSent
            PromptCount = [int](Get-PropertyValue -Object $lastPrompt -Name "prompt_count" -Default 0)
            PromptAttempts = [int](Get-PropertyValue -Object $lastPrompt -Name "prompt_attempts" -Default 0)
            InputMethod = [string](Get-PropertyValue -Object $lastPrompt -Name "input_method" -Default "")
            ConfirmedWorkObserved = Convert-ToBoolean (Get-PropertyValue -Object $lastPrompt -Name "confirmed_work_observed" -Default $false)
            Error = $lastPromptError
        }
        UsagePause = [pscustomobject]@{
            Active = [bool]$usagePauseActive
            PausedAt = if ($null -eq $lastUsagePausedTime) { $null } else { $lastUsagePausedTime.ToString("o") }
            ResumedAt = if ($null -eq $lastUsageResumedTime) { $null } else { $lastUsageResumedTime.ToString("o") }
            Until = if ($null -eq $usagePauseUntil) { $null } else { $usagePauseUntil.ToString("o") }
            RemainingSeconds = Get-RemainingSeconds -Time $usagePauseUntil
            Reason = [string](Get-PropertyValue -Object $lastUsagePaused -Name "reason" -Default "")
            FallbackUsed = Convert-ToBoolean (Get-PropertyValue -Object $lastUsagePaused -Name "fallback_used" -Default $false)
            MatchedText = [string](Get-PropertyValue -Object $lastUsagePaused -Name "matched_text" -Default "")
        }
        LastStopped = [pscustomobject]@{
            At = if ($null -eq $lastStoppedTime) { $null } else { $lastStoppedTime.ToString("o") }
            AgeSeconds = Get-AgeSeconds -Time $lastStoppedTime
            Reason = $lastStoppedReason
        }
    }
}

do {
    $summary = Get-ContinuumSummary
    if ($Json) {
        $summary | ConvertTo-Json -Depth 10
    }
    else {
        $summary | Format-List
    }

    if ($Watch) {
        Start-Sleep -Seconds $RefreshSeconds
    }
} while ($Watch)
