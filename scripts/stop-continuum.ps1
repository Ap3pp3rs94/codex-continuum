[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [ValidateRange(0, 2147483647)]
    [int]$WatcherProcessId = 0,

    [ValidateRange(0, 2147483647)]
    [int]$TargetProcessId = 0,

    [string]$SessionId = "",

    [string]$ReceiptPath = "",

    [switch]$Json
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

function Get-ContinuumWatcherProcess {
    $watcherPattern = "(?i)-File\s+.*(codex-continuum|codex-live-continue|start-codex-continuum|start-continuum)\.ps1"
    $commandPattern = "(?i)(get-continuum-status|stop-continuum|update-continuum)\.ps1|(?:^|\s)(?:status|get-status|stop|stop-continuum|update|update-continuum|--status|-Status|-ProbeOnly)(?:\s|$)"

    return @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                [int]$_.ProcessId -ne $PID -and
                $commandLine -match $watcherPattern -and
                $commandLine -notmatch $commandPattern
            } |
            Select-Object ProcessId, ParentProcessId, Name, CommandLine
    )
}

function Write-StopReceipt {
    param(
        [object[]]$Stopped,
        [object[]]$Matched
    )

    $directory = Split-Path -Parent $ReceiptPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $payload = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString("o")
        event = "codex_live_continue.stop_requested"
        stopped_process_ids = @($Stopped | ForEach-Object { [int]$_.ProcessId })
        matched_process_ids = @($Matched | ForEach-Object { [int]$_.ProcessId })
        watcher_process_id = $WatcherProcessId
        target_process_id = $TargetProcessId
        session_id = $SessionId
        what_if = [bool]$WhatIfPreference
    }

    Add-Content -LiteralPath $ReceiptPath -Value (($payload | ConvertTo-Json -Compress -Depth 6)) -Encoding UTF8
}

$watchers = @(Get-ContinuumWatcherProcess)

if ($WatcherProcessId -gt 0) {
    $watchers = @($watchers | Where-Object { [int]$_.ProcessId -eq $WatcherProcessId })
}

if ($TargetProcessId -gt 0) {
    $watchers = @($watchers | Where-Object { [string]$_.CommandLine -match "(?i)-TargetProcessId\s+[`"']?$TargetProcessId[`"']?(?:\s|$)" })
}

if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $sessionPattern = [regex]::Escape($SessionId)
    $watchers = @($watchers | Where-Object { [string]$_.CommandLine -match "(?i)-SessionId\s+[`"']?$sessionPattern[`"']?(?:\s|$)" })
}

$stopped = New-Object System.Collections.ArrayList
foreach ($watcher in $watchers) {
    $target = "PID $($watcher.ProcessId) ($($watcher.Name))"
    if ($PSCmdlet.ShouldProcess($target, "Stop Codex Continuum watcher")) {
        Stop-Process -Id ([int]$watcher.ProcessId) -Force -ErrorAction Stop
        [void]$stopped.Add($watcher)
    }
}

if ($watchers.Count -gt 0) {
    Write-StopReceipt -Stopped @($stopped) -Matched @($watchers)
}

$summary = [pscustomobject]@{
    Matched = [int]$watchers.Count
    Stopped = [int]$stopped.Count
    StoppedProcessIds = @($stopped | ForEach-Object { [int]$_.ProcessId })
    ReceiptPath = $ReceiptPath
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 5
}
else {
    if ($watchers.Count -eq 0) {
        Write-Host "No Codex Continuum watcher processes matched."
    }
    else {
        Write-Host "Stopped $($stopped.Count) Codex Continuum watcher process(es)."
        if ($stopped.Count -gt 0) {
            Write-Host "PIDs: $(@($stopped | ForEach-Object { [int]$_.ProcessId }) -join ', ')"
        }
    }
}
