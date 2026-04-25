[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
param(
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 256)]
    [string]$Prompt = "continue",

    [ValidateNotNullOrEmpty()]
    [string]$StatusPattern = "\bWorking\b",

    [string]$TitleWorkingPattern = "(^|:\s*)[\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f]\s+",

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
    [int]$AttachDelaySeconds = 5,

    [ValidateRange(0, 2147483647)]
    [int]$TargetProcessId = 0,

    [ValidateRange(0, [long]::MaxValue)]
    [long]$TargetWindowHandle = 0,

    [ValidateRange(0.05, 1.0)]
    [double]$BottomFraction = 0.30,

    [ValidateRange(1, 50)]
    [int]$TailLines = 8,

    [ValidateRange(0, 86400)]
    [int]$TimeoutSeconds = 0,

    [string]$WindowTitlePattern = "",

    [string]$SessionId = "",

    [string]$ReceiptPath = "",

    [switch]$AllowFullWindowFallback,

    [switch]$RequireObservedWorkingBeforeFirstPrompt,

    [switch]$ProbeOnly,

    [switch]$ExitOnFocusLoss,

    [switch]$PauseWhenTargetNotForeground,

    [switch]$VerboseStatusText
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "codex-live-continue.ps1 only supports Windows live sessions."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$receiptPath = if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    Join-Path $repoRoot "data\operator\codex-live-continue.jsonl"
}
else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReceiptPath)
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

if (-not ("CodexContinuumWindow" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class CodexContinuumWindow
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private const int INPUT_KEYBOARD = 1;
    private const int SW_RESTORE = 9;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_UNICODE = 0x0004;
    private const ushort VK_MENU = 0x12;
    private const ushort VK_ESCAPE = 0x1B;
    private const ushort VK_RETURN = 0x0D;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public InputUnion u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public static string GetTitle(IntPtr hWnd)
    {
        StringBuilder title = new StringBuilder(512);
        GetWindowText(hWnd, title, title.Capacity);
        return title.ToString();
    }

    public static bool ForceForegroundWindow(IntPtr hWnd)
    {
        if (!IsWindow(hWnd))
        {
            return false;
        }

        IntPtr foreground = GetForegroundWindow();
        if (foreground == hWnd)
        {
            return true;
        }

        ShowWindowAsync(hWnd, SW_RESTORE);

        uint foregroundProcessId;
        uint targetProcessId;
        uint currentThread = GetCurrentThreadId();
        uint foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, out foregroundProcessId);
        uint targetThread = GetWindowThreadProcessId(hWnd, out targetProcessId);
        bool attachedForeground = false;
        bool attachedTarget = false;

        try
        {
            if (foregroundThread != 0 && foregroundThread != currentThread)
            {
                attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
            }

            if (targetThread != 0 && targetThread != currentThread)
            {
                attachedTarget = AttachThreadInput(currentThread, targetThread, true);
            }

            try
            {
                SendVirtualKey(VK_MENU);
            }
            catch
            {
            }

            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
        }
        finally
        {
            if (attachedTarget)
            {
                AttachThreadInput(currentThread, targetThread, false);
            }

            if (attachedForeground)
            {
                AttachThreadInput(currentThread, foregroundThread, false);
            }
        }

        return GetForegroundWindow() == hWnd;
    }

    private static void SendUnicodeChar(char value)
    {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].u.ki.wScan = value;
        inputs[0].u.ki.dwFlags = KEYEVENTF_UNICODE;

        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].u.ki.wScan = value;
        inputs[1].u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;

        uint sent = SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 2)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SendInput failed while sending text.");
        }
    }

    private static void SendVirtualKey(ushort value)
    {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = value;

        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].u.ki.wVk = value;
        inputs[1].u.ki.dwFlags = KEYEVENTF_KEYUP;

        uint sent = SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 2)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SendInput failed while sending a key.");
        }
    }

    public static void SendUnicodeText(string text, bool pressEnter)
    {
        if (!String.IsNullOrEmpty(text))
        {
            foreach (char value in text)
            {
                SendUnicodeChar(value);
            }
        }

        if (pressEnter)
        {
            SendVirtualKey(VK_RETURN);
        }
    }

    public static void SendEnterKey()
    {
        SendVirtualKey(VK_RETURN);
    }

    public static void SendAltKey()
    {
        SendVirtualKey(VK_MENU);
    }

    public static void SendEscapeKey()
    {
        SendVirtualKey(VK_ESCAPE);
    }
}
"@
}

function Write-Receipt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Event,

        [hashtable]$Data = @{}
    )

    $directory = Split-Path -Parent $receiptPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $payload = [ordered]@{
        ts = [DateTimeOffset]::UtcNow.ToString("o")
        event = $Event
    }

    foreach ($key in $Data.Keys) {
        $payload[$key] = $Data[$key]
    }

    Add-Content -LiteralPath $receiptPath -Value (($payload | ConvertTo-Json -Compress -Depth 6)) -Encoding UTF8
}

function Get-ElementText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element
    )

    $values = New-Object System.Collections.Generic.List[string]

    try {
        $name = [string]$Element.Current.Name
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $values.Add($name)
        }
    }
    catch {
    }

    try {
        $pattern = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
            $value = [string]([System.Windows.Automation.ValuePattern]$pattern).Current.Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $values.Add($value)
            }
        }
    }
    catch {
    }

    try {
        $pattern = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) {
            $text = ([System.Windows.Automation.TextPattern]$pattern).DocumentRange.GetText(20000)
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $values.Add($text)
            }
        }
    }
    catch {
    }

    return ($values -join "`n")
}

function Select-TailText {
    param(
        [string]$Text,

        [ValidateRange(1, 50)]
        [int]$LineCount = 8
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $lines = @(
        $Text -split "\r?\n" |
            ForEach-Object { $_.TrimEnd() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($lines.Count -eq 0) {
        return ""
    }

    if ($lines.Count -le $LineCount) {
        return ($lines -join "`n")
    }

    return (($lines | Select-Object -Last $LineCount) -join "`n")
}

function Add-AccessibleText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.AutomationElement]$Element,

        [Parameter(Mandatory = $true)]
        [System.Windows.Automation.TreeWalker]$Walker,

        [Parameter(Mandatory = $true)]
        [double]$BottomStart,

        [Parameter(Mandatory = $true)]
        [double]$WindowHeight,

        [Parameter(Mandatory = $true)]
        [ref]$Texts,

        [Parameter(Mandatory = $true)]
        [ref]$IncludedCount,

        [int]$Depth = 0
    )

    if ($Depth -gt 8) {
        return
    }

    $include = $false
    $useTailOnly = $false
    try {
        $rect = $Element.Current.BoundingRectangle
        if (-not $rect.IsEmpty) {
            $include = ($rect.Bottom -ge $BottomStart)
            $useTailOnly = ($rect.Height -ge ($WindowHeight * 0.60))
        }
    }
    catch {
        $include = $false
    }

    if ($include) {
        $text = Get-ElementText -Element $Element
        if ($useTailOnly) {
            $text = Select-TailText -Text $text -LineCount $TailLines
        }
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $Texts.Value.Add($text)
            $IncludedCount.Value = [int]$IncludedCount.Value + 1
        }
    }

    try {
        $child = $Walker.GetFirstChild($Element)
        while ($null -ne $child) {
            Add-AccessibleText -Element $child -Walker $Walker -BottomStart $BottomStart -WindowHeight $WindowHeight -Texts $Texts -IncludedCount $IncludedCount -Depth ($Depth + 1)
            $child = $Walker.GetNextSibling($child)
        }
    }
    catch {
    }
}

function Get-LiveSessionStatusText {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle
    )

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
    if ($null -eq $root) {
        return [pscustomobject]@{
            Text = ""
            IncludedCount = 0
            UsedFallback = $false
        }
    }

    $rect = $root.Current.BoundingRectangle
    $bottomStart = $rect.Bottom - ($rect.Height * $BottomFraction)
    $texts = New-Object System.Collections.Generic.List[string]
    $included = 0
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    Add-AccessibleText -Element $root -Walker $walker -BottomStart $bottomStart -WindowHeight $rect.Height -Texts ([ref]$texts) -IncludedCount ([ref]$included)

    $usedFallback = $false
    if ($texts.Count -eq 0 -and $AllowFullWindowFallback) {
        $usedFallback = $true
        Add-AccessibleText -Element $root -Walker $walker -BottomStart $rect.Top -WindowHeight $rect.Height -Texts ([ref]$texts) -IncludedCount ([ref]$included)
    }

    return [pscustomobject]@{
        Text = ($texts -join "`n")
        IncludedCount = $included
        UsedFallback = $usedFallback
    }
}

function Get-LiveSessionWorkingState {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle
    )

    $status = Get-LiveSessionStatusText -Handle $Handle
    $title = [CodexContinuumWindow]::GetTitle($Handle)
    $workingByText = ([string]$status.Text) -match $StatusPattern
    $workingByTitle = (-not [string]::IsNullOrWhiteSpace($TitleWorkingPattern)) -and ($title -match $TitleWorkingPattern)
    $signal = if ($workingByText) {
        "text"
    }
    elseif ($workingByTitle) {
        "title"
    }
    else {
        "none"
    }

    return [pscustomobject]@{
        Text = [string]$status.Text
        Title = $title
        Working = [bool]($workingByText -or $workingByTitle)
        WorkingSignal = $signal
        IncludedCount = [int]$status.IncludedCount
        UsedFallback = [bool]$status.UsedFallback
    }
}

function Set-LiveSessionForeground {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle
    )

    for ($attempt = 1; $attempt -le 5; $attempt += 1) {
        if ([CodexContinuumWindow]::GetForegroundWindow() -eq $Handle) {
            return "already-foreground"
        }

        if ([CodexContinuumWindow]::ForceForegroundWindow($Handle)) {
            Start-Sleep -Milliseconds 200
            if ([CodexContinuumWindow]::GetForegroundWindow() -eq $Handle) {
                return "force-foreground-$attempt"
            }
        }

        try {
            [CodexContinuumWindow]::SendAltKey()
        }
        catch {
            [System.Windows.Forms.SendKeys]::SendWait("%")
        }

        Start-Sleep -Milliseconds 150
        [void][CodexContinuumWindow]::SetForegroundWindow($Handle)
        Start-Sleep -Milliseconds 250
    }

    return "foreground-failed"
}

function Send-ContinuePrompt {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle
    )

    $activationMethod = Set-LiveSessionForeground -Handle $Handle
    if ([CodexContinuumWindow]::GetForegroundWindow() -ne $Handle) {
        $currentHandle = [CodexContinuumWindow]::GetForegroundWindow()
        $currentHandleId = ("0x{0:x}" -f $currentHandle.ToInt64())
        throw "target_window_not_foreground activation=$activationMethod current=$currentHandleId"
    }

    try {
        [CodexContinuumWindow]::SendEscapeKey()
        Start-Sleep -Milliseconds 150
    }
    catch {
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        Start-Sleep -Milliseconds 150
    }

    $textMethod = ""
    try {
        [CodexContinuumWindow]::SendUnicodeText($Prompt, $false)
        $textMethod = "sendinput-text"
    }
    catch {
        [System.Windows.Forms.SendKeys]::SendWait($Prompt)
        $textMethod = "sendkeys-text"
    }

    Start-Sleep -Milliseconds 100

    $submitMethods = New-Object System.Collections.Generic.List[string]
    foreach ($submitMethod in @("sendkeys-tilde", "sendkeys-ctrl-m", "sendinput-enter", "sendkeys-enter")) {
        $submitFailed = $false
        switch ($submitMethod) {
            "sendkeys-tilde" {
                [System.Windows.Forms.SendKeys]::SendWait("~")
            }
            "sendkeys-ctrl-m" {
                [System.Windows.Forms.SendKeys]::SendWait("^m")
            }
            "sendinput-enter" {
                try {
                    [CodexContinuumWindow]::SendEnterKey()
                }
                catch {
                    $submitMethods.Add("$submitMethod-failed")
                    $submitFailed = $true
                }
            }
            "sendkeys-enter" {
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            }
        }

        if ($submitFailed) {
            continue
        }

        $submitMethods.Add($submitMethod)
        $deadline = (Get-Date).AddMilliseconds($SubmitConfirmMilliseconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 250
            $state = Get-LiveSessionWorkingState -Handle $Handle
            if ($state.Working) {
                return "$activationMethod+$textMethod+$submitMethod-confirmed-$($state.WorkingSignal)"
            }
        }
    }

    return "$activationMethod+$textMethod+$($submitMethods -join '+')-unconfirmed"
}

function Resolve-LiveSessionHandle {
    if ($TargetWindowHandle -gt 0) {
        $handle = [IntPtr]::new($TargetWindowHandle)
        if (-not [CodexContinuumWindow]::IsWindow($handle)) {
            throw "TargetWindowHandle does not resolve to a live window: $TargetWindowHandle"
        }
        return $handle
    }

    if ($TargetProcessId -gt 0) {
        $targetProcess = Get-Process -Id $TargetProcessId -ErrorAction Stop
        if ($targetProcess.MainWindowHandle -eq 0) {
            throw "TargetProcessId $TargetProcessId has no main window handle."
        }
        return [IntPtr]$targetProcess.MainWindowHandle
    }

    if ($AttachDelaySeconds -gt 0) {
    Write-Host "Focus the live Codex session now. Attaching in $AttachDelaySeconds second(s)."
    for ($remaining = $AttachDelaySeconds; $remaining -gt 0; $remaining--) {
        Write-Host "Attach in $remaining..."
        Start-Sleep -Seconds 1
    }
    }

    return [CodexContinuumWindow]::GetForegroundWindow()
}

$sessionHandle = Resolve-LiveSessionHandle
if ($sessionHandle -eq [IntPtr]::Zero) {
    throw "No foreground window is available. Focus the live Codex session and rerun this script."
}

$windowTitle = [CodexContinuumWindow]::GetTitle($sessionHandle)
if ($WindowTitlePattern -and $windowTitle -notmatch $WindowTitlePattern) {
    throw "Foreground window title does not match WindowTitlePattern. Title: $windowTitle"
}

$handleId = ("0x{0:x}" -f $sessionHandle.ToInt64())
Write-Host "Attached to live window $handleId ($windowTitle)"
Write-Host "Watching for status pattern '$StatusPattern' or title pattern '$TitleWorkingPattern' in that same live window."
Write-Host "Receipts: $receiptPath"

Write-Receipt -Event "codex_live_continue.attached" -Data @{
    handle = $handleId
    title = $windowTitle
    max_prompts = $MaxPrompts
    poll_ms = $PollMilliseconds
    stable_clear_ms = $StableClearMilliseconds
    submit_confirm_ms = $SubmitConfirmMilliseconds
    cooldown_s = $CooldownSeconds
    attach_delay_s = $AttachDelaySeconds
    target_process_id = $TargetProcessId
    target_window_handle = $TargetWindowHandle
    bottom_fraction = $BottomFraction
    tail_lines = $TailLines
    status_pattern = $StatusPattern
    title_working_pattern = $TitleWorkingPattern
    timeout_s = $TimeoutSeconds
    window_title_pattern = $WindowTitlePattern
    session_id = $SessionId
    allow_full_window_fallback = [bool]$AllowFullWindowFallback
    require_observed_working_before_first_prompt = [bool]$RequireObservedWorkingBeforeFirstPrompt
    probe_only = [bool]$ProbeOnly
    exit_on_focus_loss = [bool]$ExitOnFocusLoss
    pause_when_target_not_foreground = [bool]$PauseWhenTargetNotForeground
    what_if = [bool]$WhatIfPreference
}

if ($ProbeOnly) {
    $status = Get-LiveSessionWorkingState -Handle $sessionHandle
    $isWorking = [bool]$status.Working
    Write-Receipt -Event "codex_live_continue.probe" -Data @{
        handle = $handleId
        working = [bool]$isWorking
        working_signal = [string]$status.WorkingSignal
        title = [string]$status.Title
        included_accessible_elements = [int]$status.IncludedCount
        used_full_window_fallback = [bool]$status.UsedFallback
        text_available = -not [string]::IsNullOrWhiteSpace([string]$status.Text)
        session_id = $SessionId
    }

    Write-Host "Probe result: working=$isWorking, signal=$($status.WorkingSignal), title='$($status.Title)', accessible_elements=$($status.IncludedCount), fallback=$($status.UsedFallback)"
    if ($VerboseStatusText) {
        Write-Host "--- captured status text ---"
        Write-Host ([string]$status.Text)
        Write-Host "--- end captured status text ---"
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$status.Text)) {
        Write-Host "No bottom status text was visible through UI Automation."
    }
    exit 0
}

$startedAt = Get-Date
$observedWorking = -not [bool]$RequireObservedWorkingBeforeFirstPrompt
$clearSince = $null
$lastPromptAt = (Get-Date).AddSeconds(-1 * ($CooldownSeconds + 1))
$sentPrompts = 0
$promptAttempts = 0
$lastObservedState = $null
$focusPaused = $false
$stopReason = "ctrl_c_or_process_exit"

try {
while ($MaxPrompts -eq 0 -or $sentPrompts -lt $MaxPrompts) {
    if ($TimeoutSeconds -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
        $stopReason = "timeout"
        Write-Host "Stopped after timeout. Prompts sent: $sentPrompts"
        break
    }

    if (-not [CodexContinuumWindow]::IsWindow($sessionHandle)) {
        $stopReason = "window_closed"
        Write-Host "Stopped because the attached live window closed. Prompts sent: $sentPrompts"
        break
    }

    $foreground = [CodexContinuumWindow]::GetForegroundWindow()
    if ($foreground -ne $sessionHandle) {
        if ($ExitOnFocusLoss) {
            $stopReason = "focus_lost"
            Write-Host "Stopped because focus left the attached live session. Prompts sent: $sentPrompts"
            break
        }

        if (-not $PauseWhenTargetNotForeground) {
            if ($focusPaused) {
                $focusPaused = $false
                Write-Receipt -Event "codex_live_continue.resumed" -Data @{
                    handle = $handleId
                    reason = "watching_target_without_foreground"
                    prompts_sent = $sentPrompts
                    session_id = $SessionId
                }
                Write-Host "Resumed watching the attached live session without requiring foreground focus."
            }
        }
        else {
        if (-not $focusPaused) {
            $focusPaused = $true
            Write-Receipt -Event "codex_live_continue.paused" -Data @{
                handle = $handleId
                reason = "focus_lost"
                prompts_sent = $sentPrompts
                session_id = $SessionId
            }
            Write-Host "Paused while focus is outside the attached live session. Press Ctrl+C to stop."
        }

        Start-Sleep -Milliseconds $PollMilliseconds
        continue
        }
    }

    if ($focusPaused) {
        $focusPaused = $false
        Write-Receipt -Event "codex_live_continue.resumed" -Data @{
            handle = $handleId
            reason = "focus_returned"
            prompts_sent = $sentPrompts
            session_id = $SessionId
        }
        Write-Host "Resumed watching the attached live session."
    }

    $status = Get-LiveSessionWorkingState -Handle $sessionHandle
    $isWorking = [bool]$status.Working

    if ($lastObservedState -ne $isWorking) {
        $lastObservedState = $isWorking
        Write-Receipt -Event "codex_live_continue.status" -Data @{
            handle = $handleId
            working = [bool]$isWorking
            working_signal = [string]$status.WorkingSignal
            title = [string]$status.Title
            included_accessible_elements = [int]$status.IncludedCount
            used_full_window_fallback = [bool]$status.UsedFallback
            session_id = $SessionId
        }
    }

    if ($isWorking) {
        $observedWorking = $true
        $clearSince = $null
    }
    elseif ($observedWorking) {
        if ($null -eq $clearSince) {
            $clearSince = Get-Date
        }

        $stableClear = ((Get-Date) - $clearSince).TotalMilliseconds -ge $StableClearMilliseconds
        $cooldownClear = ((Get-Date) - $lastPromptAt).TotalSeconds -ge $CooldownSeconds

        if ($stableClear -and $cooldownClear) {
            $target = "$handleId ($windowTitle)"
            $action = "send prompt '$Prompt' to the attached live Codex session"
            $sent = $false
            $inputMethod = ""
            $sendError = ""
            if ($PSCmdlet.ShouldProcess($target, $action)) {
                $promptAttempts += 1
                try {
                    $inputMethod = Send-ContinuePrompt -Handle $sessionHandle
                    $sent = $true
                }
                catch {
                    $inputMethod = "send-failed"
                    $sendError = $_.Exception.Message
                }
            }

            if ($sent -or $WhatIfPreference) {
                $sentPrompts += 1
            }

            $lastPromptAt = Get-Date
            $confirmedWorkObserved = $sent -and ($inputMethod -match "-confirmed-")
            if ($confirmedWorkObserved) {
                $observedWorking = $true
                $clearSince = $null
                $lastObservedState = $true
                $confirmedStatus = Get-LiveSessionWorkingState -Handle $sessionHandle
                Write-Receipt -Event "codex_live_continue.status" -Data @{
                    handle = $handleId
                    working = $true
                    working_signal = "send_confirmation"
                    title = [string]$confirmedStatus.Title
                    included_accessible_elements = [int]$confirmedStatus.IncludedCount
                    used_full_window_fallback = [bool]$confirmedStatus.UsedFallback
                    session_id = $SessionId
                }
            }
            elseif ($sent -or $WhatIfPreference) {
                $observedWorking = $false
                $clearSince = $null
            }
            else {
                $observedWorking = $true
                $clearSince = Get-Date
            }

            Write-Receipt -Event "codex_live_continue.prompt" -Data @{
                handle = $handleId
                prompt = $Prompt
                sent = $sent
                what_if = [bool]$WhatIfPreference
                prompt_count = $sentPrompts
                prompt_attempts = $promptAttempts
                session_id = $SessionId
                input_method = $inputMethod
                error = $sendError
                confirmed_work_observed = [bool]$confirmedWorkObserved
            }

            if ($sent) {
                $limitLabel = if ($MaxPrompts -eq 0) { "unlimited" } else { [string]$MaxPrompts }
                Write-Host "Sent live-session continuation prompt $sentPrompts/$limitLabel."
            }
            elseif (-not [string]::IsNullOrWhiteSpace($sendError)) {
                Write-Host "Continuation send failed and will retry after cooldown: $sendError"
            }
            else {
                $limitLabel = if ($MaxPrompts -eq 0) { "unlimited" } else { [string]$MaxPrompts }
                Write-Host "Would send live-session continuation prompt $sentPrompts/$limitLabel."
            }
        }
    }

    Start-Sleep -Milliseconds $PollMilliseconds
}

if ($MaxPrompts -ne 0 -and $sentPrompts -ge $MaxPrompts -and $stopReason -eq "ctrl_c_or_process_exit") {
    $stopReason = "max_prompts"
    Write-Host "Stopped after MaxPrompts=$MaxPrompts. Prompts sent: $sentPrompts"
}
}
finally {
Write-Receipt -Event "codex_live_continue.stopped" -Data @{
    handle = $handleId
    reason = $stopReason
    prompts_sent = $sentPrompts
    prompt_attempts = $promptAttempts
    session_id = $SessionId
}
}
