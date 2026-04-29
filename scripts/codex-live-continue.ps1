[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
param(
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

    [ValidateRange(0, 86400)]
    [int]$StuckWorkingSeconds = 1800,

    [ValidateRange(0, 86400)]
    [int]$ResyncCooldownSeconds = 300,

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

    [string]$KillFlagPath = "",

    [switch]$AllowFullWindowFallback,

    [switch]$RequireObservedWorkingBeforeFirstPrompt,

    [switch]$ProbeOnly,

    [switch]$ExitOnFocusLoss,

    [switch]$PauseWhenTargetNotForeground,

    [switch]$AutoSelectApprovalChoice,

    [switch]$DisableUsageLimitPause,

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

$killFlagPath = if ([string]::IsNullOrWhiteSpace($KillFlagPath)) {
    Join-Path (Split-Path -Parent $receiptPath) "codex-live-continue.kill"
}
else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KillFlagPath)
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

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

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
    private const int STD_INPUT_HANDLE = -10;
    private const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    private const uint ENABLE_EXTENDED_FLAGS = 0x0080;

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

    public static bool DisableQuickEditMode(out uint originalMode, out uint newMode, out int errorCode)
    {
        originalMode = 0;
        newMode = 0;
        errorCode = 0;

        IntPtr stdin = GetStdHandle(STD_INPUT_HANDLE);
        if (stdin == IntPtr.Zero || stdin == new IntPtr(-1))
        {
            errorCode = Marshal.GetLastWin32Error();
            return false;
        }

        uint mode;
        if (!GetConsoleMode(stdin, out mode))
        {
            errorCode = Marshal.GetLastWin32Error();
            return false;
        }

        originalMode = mode;
        newMode = (mode | ENABLE_EXTENDED_FLAGS) & ~ENABLE_QUICK_EDIT_MODE;
        if (newMode == mode)
        {
            return true;
        }

        if (!SetConsoleMode(stdin, newMode))
        {
            errorCode = Marshal.GetLastWin32Error();
            return false;
        }

        return true;
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

function Disable-WatcherConsoleQuickEdit {
    $originalMode = [uint32]0
    $newMode = [uint32]0
    $errorCode = 0
    $success = [CodexContinuumWindow]::DisableQuickEditMode([ref]$originalMode, [ref]$newMode, [ref]$errorCode)

    return [pscustomobject]@{
        Success = [bool]$success
        OriginalMode = [int64]$originalMode
        Mode = [int64]$newMode
        Changed = [bool]($success -and $originalMode -ne $newMode)
        ErrorCode = [int]$errorCode
    }
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
        [IntPtr]$Handle,

        [switch]$FullWindow
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
    $bottomStart = if ($FullWindow) { $rect.Top } else { $rect.Bottom - ($rect.Height * $BottomFraction) }
    $texts = New-Object System.Collections.Generic.List[string]
    $included = 0
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    Add-AccessibleText -Element $root -Walker $walker -BottomStart $bottomStart -WindowHeight $rect.Height -Texts ([ref]$texts) -IncludedCount ([ref]$included)

    $usedFallback = [bool]$FullWindow
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
    $workingByText = ([string]$status.Text) -cmatch $StatusPattern
    $backgroundWaitByText = ([string]$status.Text) -cmatch $BackgroundWaitPattern
    $workingByTitle = (-not [string]::IsNullOrWhiteSpace($TitleWorkingPattern)) -and ($title -match $TitleWorkingPattern)
    $signal = if ($workingByText) {
        "text"
    }
    elseif ($backgroundWaitByText) {
        "background_wait"
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
        Working = [bool]($workingByText -or $backgroundWaitByText -or $workingByTitle)
        WorkingSignal = $signal
        IncludedCount = [int]$status.IncludedCount
        UsedFallback = [bool]$status.UsedFallback
    }
}

function Get-StatusSnapshotHash {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Status
    )

    $raw = @(
        [string]$Status.Title,
        [string]$Status.WorkingSignal,
        [string]$Status.IncludedCount,
        [string]$Status.UsedFallback,
        [string]$Status.Text
    ) -join "`n---codex-continuum-status---`n"

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hashBytes = $sha.ComputeHash($bytes)
        return (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha.Dispose()
    }
}

function Sync-LiveSessionHandle {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$CurrentHandle
    )

    $method = "current_handle"
    $newHandle = $CurrentHandle

    if ($TargetWindowHandle -gt 0) {
        $candidate = [IntPtr]::new([long]$TargetWindowHandle)
        if (-not [CodexContinuumWindow]::IsWindow($candidate)) {
            throw "TargetWindowHandle is no longer a live window: $TargetWindowHandle"
        }

        $newHandle = $candidate
        $method = "target_window_handle"
    }
    elseif ($TargetProcessId -gt 0) {
        $targetProcess = Get-Process -Id $TargetProcessId -ErrorAction Stop
        if ($targetProcess.MainWindowHandle -eq 0) {
            throw "TargetProcessId $TargetProcessId has no main window handle."
        }

        $newHandle = [IntPtr]$targetProcess.MainWindowHandle
        $method = "target_process_id"
    }
    elseif (-not [CodexContinuumWindow]::IsWindow($newHandle)) {
        throw "Current session window is no longer live and no explicit target was provided."
    }

    return [pscustomobject]@{
        Handle = $newHandle
        Method = $method
        Title = [CodexContinuumWindow]::GetTitle($newHandle)
        Changed = ($newHandle -ne $CurrentHandle)
    }
}

function Select-UsageWarningContext {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $lines = @(
        $Text -split "\r?\n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($line in $lines) {
        if ($line -match $UsageWarningPattern) {
            if ($line.Length -gt 500) {
                return $line.Substring(0, 500)
            }

            return $line
        }
    }

    $tail = Select-TailText -Text $Text -LineCount $TailLines
    if ($tail.Length -gt 500) {
        return $tail.Substring(0, 500)
    }

    return $tail
}

function Test-ActionableUsageWarningContext {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return (
        $Text -match "(?i)\b(?:try again|resets?|reset|available|renews?)\s+(?:at|in|on)\b" -or
        $Text -match "(?i)\b(?:usage|rate|quota|message|token)\s+(?:limit|cap|quota)\s+(?:reached|exceeded)\b" -or
        $Text -match "(?i)\b(?:reached|exceeded|hit)\s+(?:your\s+)?(?:usage|rate|message|token|quota)\s+(?:limit|cap|quota)\b" -or
        $Text -match "(?i)\blimit\s+(?:reached|exceeded)\b"
    )
}

function ConvertTo-UsagePauseSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DurationText
    )

    $seconds = 0.0
    $matches = [regex]::Matches($DurationText, "(?i)(?<value>\d+(?:\.\d+)?)\s*(?<unit>h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)")
    foreach ($match in $matches) {
        $value = [double]::Parse($match.Groups["value"].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        $unit = $match.Groups["unit"].Value.ToLowerInvariant()
        if ($unit -in @("h", "hr", "hrs", "hour", "hours")) {
            $seconds += ($value * 3600)
        }
        elseif ($unit -in @("m", "min", "mins", "minute", "minutes")) {
            $seconds += ($value * 60)
        }
        else {
            $seconds += $value
        }
    }

    return [int][Math]::Ceiling($seconds)
}

function Get-UsagePauseState {
    param(
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$Now
    )

    if ($DisableUsageLimitPause -or [string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch $UsageWarningPattern) {
        return [pscustomobject]@{
            Detected = $false
            PauseUntil = $null
            Reason = ""
            MatchedText = ""
            FallbackUsed = $false
        }
    }

    $context = Select-UsageWarningContext -Text $Text
    if (-not (Test-ActionableUsageWarningContext -Text $context)) {
        return [pscustomobject]@{
            Detected = $false
            PauseUntil = $null
            Reason = ""
            MatchedText = $context
            FallbackUsed = $false
        }
    }

    $pauseUntil = $null
    $reason = ""
    $fallbackUsed = $false

    $isoMatch = [regex]::Match($context, "(?<ts>\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:\s?(?:Z|[+-]\d{2}:?\d{2}))?)")
    if ($isoMatch.Success) {
        $parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse($isoMatch.Groups["ts"].Value, [ref]$parsed) -and $parsed -gt $Now) {
            $pauseUntil = $parsed
            $reason = "iso_reset_time"
        }
    }

    if ($null -eq $pauseUntil) {
        $relativeMatch = [regex]::Match($context, "(?i)\b(?:in|after)\s+(?<duration>(?:\d+(?:\.\d+)?\s*(?:h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)\s*){1,4})")
        if ($relativeMatch.Success) {
            $seconds = ConvertTo-UsagePauseSeconds -DurationText $relativeMatch.Groups["duration"].Value
            if ($seconds -gt 0) {
                $pauseUntil = $Now.AddSeconds($seconds)
                $reason = "relative_reset_time"
            }
        }
    }

    if ($null -eq $pauseUntil) {
        $timeMatch = [regex]::Match($context, "(?i)\b(?:resets?|reset|try again|available|renews?)\s+(?:at|on)\s+(?<hour>\d{1,2})(?::(?<minute>\d{2}))?\s*(?<ampm>a\.?m\.?|p\.?m\.?|am|pm)?")
        if ($timeMatch.Success) {
            $hour = [int]$timeMatch.Groups["hour"].Value
            $minute = if ($timeMatch.Groups["minute"].Success) { [int]$timeMatch.Groups["minute"].Value } else { 0 }
            $ampm = $timeMatch.Groups["ampm"].Value.ToLowerInvariant().Replace(".", "")

            if ($hour -ge 1 -and $hour -le 24 -and $minute -ge 0 -and $minute -le 59) {
                if ($ampm -eq "pm" -and $hour -lt 12) {
                    $hour += 12
                }
                elseif ($ampm -eq "am" -and $hour -eq 12) {
                    $hour = 0
                }
                elseif ([string]::IsNullOrWhiteSpace($ampm) -and $hour -eq 24) {
                    $hour = 0
                }

                if ($hour -ge 0 -and $hour -le 23) {
                    $candidateDate = [datetime]::new($Now.Year, $Now.Month, $Now.Day, $hour, $minute, 0)
                    $candidate = [DateTimeOffset]::new($candidateDate, $Now.Offset)
                    if ($candidate -le $Now) {
                        $candidate = $candidate.AddDays(1)
                    }

                    $pauseUntil = $candidate
                    $reason = "clock_reset_time"
                }
            }
        }
    }

    if ($null -eq $pauseUntil -and $UsagePauseFallbackSeconds -gt 0) {
        $pauseUntil = $Now.AddSeconds($UsagePauseFallbackSeconds)
        $reason = "fallback_reset_time"
        $fallbackUsed = $true
    }

    return [pscustomobject]@{
        Detected = $true
        PauseUntil = $pauseUntil
        Reason = $reason
        MatchedText = $context
        FallbackUsed = $fallbackUsed
    }
}

function Get-ApprovalPromptMatch {
    param(
        [string]$Text,

        [string]$Title = "",

        [string]$ScanScope = "bottom"
    )

    if (-not $AutoSelectApprovalChoice) {
        return [pscustomobject]@{
            Detected = $false
            Context = ""
            Choice = $ApprovalChoice
            ChoiceReason = "not_detected"
            ScanScope = $ScanScope
        }
    }

    $approvalTailLines = [Math]::Min(50, [Math]::Max($TailLines, 30))
    $scanText = if ([string]::IsNullOrWhiteSpace($Text)) { "" } else { Select-TailText -Text $Text -LineCount $approvalTailLines }
    $numberedChoices = [regex]::Matches($scanText, "(?m)^\s*[1-9][\.)]\s+\S")
    if ($numberedChoices.Count -lt 2 -or $scanText -notmatch $ApprovalPromptPattern) {
        return [pscustomobject]@{
            Detected = $false
            Context = ""
            Choice = $ApprovalChoice
            ChoiceReason = "not_detected"
            ScanScope = $ScanScope
        }
    }

    $context = $scanText
    if ($context.Length -gt 1000) {
        $context = $context.Substring(0, 1000)
    }

    $choice = $ApprovalChoice
    $choiceReason = "default"
    if ($scanText -match $DoNotAskAgainApprovalPattern) {
        $choice = $DoNotAskAgainApprovalChoice
        $choiceReason = "do_not_ask_again"
    }

    return [pscustomobject]@{
        Detected = $true
        Context = $context
        Choice = $choice
        ChoiceReason = $choiceReason
        ScanScope = $ScanScope
    }
}

function Get-InteractivePromptBlock {
    param(
        [string]$Text,

        [string]$Title = "",

        [string]$ScanScope = "bottom"
    )

    $approvalTailLines = [Math]::Min(50, [Math]::Max($TailLines, 30))
    $scanText = Select-TailText -Text $Text -LineCount $approvalTailLines
    $numberedChoices = [regex]::Matches($scanText, "(?m)^\s*[1-9][\.)]\s+\S")
    $textLooksInteractive = (-not [string]::IsNullOrWhiteSpace($scanText)) -and ($scanText -match $InteractivePromptBlockPattern)
    $commandPromptText = (-not [string]::IsNullOrWhiteSpace($scanText)) -and ($scanText -match "(?is)(would you like to run|run the following command|yes,\s*proceed|tell codex what to do differently)")

    if (-not ($commandPromptText -or ($textLooksInteractive -and $numberedChoices.Count -ge 2))) {
        return [pscustomobject]@{
            Detected = $false
            Context = ""
            BlockReason = "not_detected"
            ScanScope = $ScanScope
        }
    }

    $context = $scanText
    if ($context.Length -gt 1000) {
        $context = $context.Substring(0, 1000)
    }

    $blockReason = if ($commandPromptText) {
        "command_prompt"
    }
    else {
        "numbered_prompt"
    }

    return [pscustomobject]@{
        Detected = $true
        Context = $context
        BlockReason = $blockReason
        ScanScope = $ScanScope
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

function Send-ApprovalChoice {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Handle,

        [Parameter(Mandatory = $true)]
        [string]$Choice
    )

    $activationMethod = Set-LiveSessionForeground -Handle $Handle
    if ([CodexContinuumWindow]::GetForegroundWindow() -ne $Handle) {
        $currentHandle = [CodexContinuumWindow]::GetForegroundWindow()
        $currentHandleId = ("0x{0:x}" -f $currentHandle.ToInt64())
        throw "target_window_not_foreground activation=$activationMethod current=$currentHandleId"
    }

    $choiceMethod = ""
    try {
        [CodexContinuumWindow]::SendUnicodeText($Choice, $false)
        $choiceMethod = "sendinput-choice"
    }
    catch {
        [System.Windows.Forms.SendKeys]::SendWait($Choice)
        $choiceMethod = "sendkeys-choice"
    }

    Start-Sleep -Milliseconds 100

    try {
        [CodexContinuumWindow]::SendEnterKey()
        return "$activationMethod+$choiceMethod+sendinput-enter"
    }
    catch {
        [System.Windows.Forms.SendKeys]::SendWait("~")
        return "$activationMethod+$choiceMethod+sendkeys-tilde"
    }
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

function Clear-ConsoleSelectionMode {
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

    $escapeMethod = ""
    try {
        [CodexContinuumWindow]::SendEscapeKey()
        $escapeMethod = "sendinput-escape"
    }
    catch {
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        $escapeMethod = "sendkeys-escape"
    }

    Start-Sleep -Milliseconds 200
    return "$activationMethod+$escapeMethod"
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

$watcherConsoleMode = Disable-WatcherConsoleQuickEdit
Write-Receipt -Event "codex_live_continue.console_mode" -Data @{
    quick_edit_disabled = [bool]$watcherConsoleMode.Success
    changed = [bool]$watcherConsoleMode.Changed
    original_mode = [int64]$watcherConsoleMode.OriginalMode
    mode = [int64]$watcherConsoleMode.Mode
    error_code = [int]$watcherConsoleMode.ErrorCode
    session_id = $SessionId
}
if ([bool]$watcherConsoleMode.Success) {
    Write-Host "Watcher console QuickEdit selection freeze guard is active."
}
else {
    Write-Host "Watcher console QuickEdit guard could not be enabled; error code $($watcherConsoleMode.ErrorCode)."
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
    max_failed_submit_attempts = $MaxFailedSubmitAttempts
    stuck_working_s = $StuckWorkingSeconds
    resync_cooldown_s = $ResyncCooldownSeconds
    attach_delay_s = $AttachDelaySeconds
    target_process_id = $TargetProcessId
    target_window_handle = $TargetWindowHandle
    bottom_fraction = $BottomFraction
    tail_lines = $TailLines
    status_pattern = $StatusPattern
    background_wait_pattern = $BackgroundWaitPattern
    title_working_pattern = $TitleWorkingPattern
    usage_warning_pattern = $UsageWarningPattern
    approval_prompt_pattern = $ApprovalPromptPattern
    interactive_prompt_block_pattern = $InteractivePromptBlockPattern
    approval_choice = $ApprovalChoice
    do_not_ask_again_approval_pattern = $DoNotAskAgainApprovalPattern
    do_not_ask_again_approval_choice = $DoNotAskAgainApprovalChoice
    approval_choice_cooldown_s = $ApprovalChoiceCooldownSeconds
    usage_pause_fallback_s = $UsagePauseFallbackSeconds
    timeout_s = $TimeoutSeconds
    window_title_pattern = $WindowTitlePattern
    session_id = $SessionId
    kill_flag_path = $killFlagPath
    allow_full_window_fallback = [bool]$AllowFullWindowFallback
    require_observed_working_before_first_prompt = [bool]$RequireObservedWorkingBeforeFirstPrompt
    probe_only = [bool]$ProbeOnly
    exit_on_focus_loss = [bool]$ExitOnFocusLoss
    pause_when_target_not_foreground = [bool]$PauseWhenTargetNotForeground
    auto_select_approval_choice = [bool]$AutoSelectApprovalChoice
    disable_usage_limit_pause = [bool]$DisableUsageLimitPause
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
$consecutiveFailedSubmitAttempts = 0
$lastApprovalChoiceAt = (Get-Date).AddSeconds(-1 * ($ApprovalChoiceCooldownSeconds + 1))
$approvalChoicesSent = 0
$approvalChoiceAttempts = 0
$lastInteractivePromptBlockAt = (Get-Date).AddSeconds(-11)
$interactivePromptBlocks = 0
$lastObservedState = $null
$lastWorkingSnapshotHash = ""
$workingSnapshotSince = $null
$staleWorkingIgnoreHash = ""
$lastStuckResyncAt = (Get-Date).AddSeconds(-1 * ($ResyncCooldownSeconds + 1))
$stuckResyncCount = 0
$focusPaused = $false
$usagePausedUntil = $null
$usagePauseReason = ""
$usagePauseMatchedText = ""
$usagePauseFallbackUsed = $false
$stopReason = "ctrl_c_or_process_exit"

try {
while ($MaxPrompts -eq 0 -or $sentPrompts -lt $MaxPrompts) {
    if (Test-Path -LiteralPath $killFlagPath) {
        $stopReason = "kill_flag"
        Write-Host "Stopped because kill flag exists at $killFlagPath. Prompts sent: $sentPrompts"
        break
    }

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

    $currentTitle = [CodexContinuumWindow]::GetTitle($sessionHandle)
    if ($currentTitle -match "(?i)^Select\b") {
        $clearMethod = ""
        $clearError = ""
        try {
            $clearMethod = Clear-ConsoleSelectionMode -Handle $sessionHandle
        }
        catch {
            $clearMethod = "selection-clear-failed"
            $clearError = $_.Exception.Message
        }

        Write-Receipt -Event "codex_live_continue.selection_mode_cleared" -Data @{
            handle = $handleId
            title = $currentTitle
            clear_method = $clearMethod
            error = $clearError
            prompts_sent = $sentPrompts
            session_id = $SessionId
        }

        if ([string]::IsNullOrWhiteSpace($clearError)) {
            Write-Host "Cleared Windows console selection mode for the attached live session."
        }
        else {
            Write-Host "Console selection mode clear failed and will retry: $clearError"
        }

        Start-Sleep -Milliseconds $PollMilliseconds
        continue
    }

    $status = Get-LiveSessionWorkingState -Handle $sessionHandle
    $isWorking = [bool]$status.Working
    $effectiveWorkingSignal = [string]$status.WorkingSignal
    $statusSnapshotHash = Get-StatusSnapshotHash -Status $status
    $staleWorkingForcedIdle = $false
    $stuckWorkingSeconds = $null

    if ($isWorking) {
        $nowForStuckCheck = Get-Date
        if ($statusSnapshotHash -ne $lastWorkingSnapshotHash) {
            $lastWorkingSnapshotHash = $statusSnapshotHash
            $workingSnapshotSince = $nowForStuckCheck
        }
        elseif ($null -eq $workingSnapshotSince) {
            $workingSnapshotSince = $nowForStuckCheck
        }

        $stuckWorkingSeconds = [int][Math]::Floor(($nowForStuckCheck - $workingSnapshotSince).TotalSeconds)
        $resyncCooldownClear = (($nowForStuckCheck - $lastStuckResyncAt).TotalSeconds -ge $ResyncCooldownSeconds)
        if ($StuckWorkingSeconds -gt 0 -and $stuckWorkingSeconds -ge $StuckWorkingSeconds -and $resyncCooldownClear) {
            $oldHandleId = $handleId
            $oldTitle = [string]$status.Title
            $oldSignal = [string]$status.WorkingSignal
            $oldSnapshotHash = $statusSnapshotHash
            $resyncMethod = ""
            $resyncError = ""

            try {
                $sync = Sync-LiveSessionHandle -CurrentHandle $sessionHandle
                $sessionHandle = [IntPtr]$sync.Handle
                $handleId = ("0x{0:x}" -f $sessionHandle.ToInt64())
                $windowTitle = [string]$sync.Title
                $resyncMethod = [string]$sync.Method
                $status = Get-LiveSessionWorkingState -Handle $sessionHandle
                $isWorking = [bool]$status.Working
                $effectiveWorkingSignal = [string]$status.WorkingSignal
                $statusSnapshotHash = Get-StatusSnapshotHash -Status $status
            }
            catch {
                $resyncMethod = "resync_failed"
                $resyncError = $_.Exception.Message
            }

            $lastStuckResyncAt = Get-Date
            $stuckResyncCount += 1
            $titleStillWorking = (-not [string]::IsNullOrWhiteSpace($TitleWorkingPattern)) -and ([string]$status.Title -match $TitleWorkingPattern)
            if ([string]::IsNullOrWhiteSpace($resyncError) -and $isWorking -and $statusSnapshotHash -eq $oldSnapshotHash -and ([string]$status.WorkingSignal -in @("text", "background_wait")) -and -not $titleStillWorking) {
                $isWorking = $false
                $effectiveWorkingSignal = "stale_text_resync"
                $staleWorkingForcedIdle = $true
                $staleWorkingIgnoreHash = $statusSnapshotHash
            }

            Write-Receipt -Event "codex_live_continue.resynced" -Data @{
                handle = $handleId
                old_handle = $oldHandleId
                changed_handle = ($handleId -ne $oldHandleId)
                reason = "stuck_working"
                method = $resyncMethod
                error = $resyncError
                unchanged_seconds = $stuckWorkingSeconds
                working_signal_before = $oldSignal
                working_signal_after = $effectiveWorkingSignal
                title_before = $oldTitle
                title_after = [string]$status.Title
                snapshot_hash = $oldSnapshotHash
                forced_idle = [bool]$staleWorkingForcedIdle
                resync_count = $stuckResyncCount
                prompts_sent = $sentPrompts
                session_id = $SessionId
            }

            if ($staleWorkingForcedIdle) {
                Write-Host "Resynced after $stuckWorkingSeconds second(s) of unchanged Working text; treating stale text as idle unless an interactive prompt is visible."
            }
            elseif ([string]::IsNullOrWhiteSpace($resyncError)) {
                Write-Host "Resynced attached live session after $stuckWorkingSeconds second(s) of unchanged Working state."
            }
            else {
                Write-Host "Working-state resync failed and will retry after cooldown: $resyncError"
            }

            $lastWorkingSnapshotHash = $statusSnapshotHash
            $workingSnapshotSince = Get-Date
        }
    }
    else {
        $lastWorkingSnapshotHash = ""
        $workingSnapshotSince = $null
    }

    if ($isWorking -and -not [string]::IsNullOrWhiteSpace($staleWorkingIgnoreHash)) {
        $titleWorkingNow = (-not [string]::IsNullOrWhiteSpace($TitleWorkingPattern)) -and ([string]$status.Title -match $TitleWorkingPattern)
        if ($statusSnapshotHash -eq $staleWorkingIgnoreHash -and ([string]$status.WorkingSignal -in @("text", "background_wait")) -and -not $titleWorkingNow) {
            $isWorking = $false
            $effectiveWorkingSignal = "stale_text_resync"
            $staleWorkingForcedIdle = $true
        }
        else {
            $staleWorkingIgnoreHash = ""
        }
    }

    $approvalPrompt = [pscustomobject]@{
        Detected = $false
        Context = ""
        Choice = $ApprovalChoice
        ChoiceReason = "not_detected"
        ScanScope = "not_scanned_working"
    }
    $interactivePromptBlock = [pscustomobject]@{
        Detected = $false
        Context = ""
        BlockReason = "not_detected"
        ScanScope = "not_scanned_working"
    }
    if (-not $isWorking) {
        $approvalStatus = Get-LiveSessionStatusText -Handle $sessionHandle -FullWindow
        $approvalText = [string]$approvalStatus.Text
        if ([string]::IsNullOrWhiteSpace($approvalText)) {
            $approvalText = [string]$status.Text
        }

        $approvalPrompt = Get-ApprovalPromptMatch -Text $approvalText -Title ([string]$status.Title) -ScanScope "full_window_tail"
        if (-not [bool]$approvalPrompt.Detected) {
            $interactivePromptBlock = Get-InteractivePromptBlock -Text $approvalText -Title ([string]$status.Title) -ScanScope "full_window_tail"
        }
    }

    if ($lastObservedState -ne $isWorking) {
        $lastObservedState = $isWorking
        Write-Receipt -Event "codex_live_continue.status" -Data @{
            handle = $handleId
            working = [bool]$isWorking
            working_signal = $effectiveWorkingSignal
            title = [string]$status.Title
            included_accessible_elements = [int]$status.IncludedCount
            used_full_window_fallback = [bool]$status.UsedFallback
            stale_working_forced_idle = [bool]$staleWorkingForcedIdle
            session_id = $SessionId
        }
    }

    if ([bool]$approvalPrompt.Detected) {
        $approvalCooldownClear = ((Get-Date) - $lastApprovalChoiceAt).TotalSeconds -ge $ApprovalChoiceCooldownSeconds
        if ($approvalCooldownClear) {
            $selectedApprovalChoice = [string]$approvalPrompt.Choice
            $selectedApprovalChoiceReason = [string]$approvalPrompt.ChoiceReason
            $target = "$handleId ($windowTitle)"
            $action = "send approval choice '$selectedApprovalChoice' to the attached live Codex session"
            $sent = $false
            $inputMethod = ""
            $sendError = ""
            if ($PSCmdlet.ShouldProcess($target, $action)) {
                $approvalChoiceAttempts += 1
                try {
                    $inputMethod = Send-ApprovalChoice -Handle $sessionHandle -Choice $selectedApprovalChoice
                    $sent = $true
                }
                catch {
                    $inputMethod = "approval-send-failed"
                    $sendError = $_.Exception.Message
                }
            }

            if ($sent -or $WhatIfPreference) {
                $approvalChoicesSent += 1
            }

            $lastApprovalChoiceAt = Get-Date
            Write-Receipt -Event "codex_live_continue.approval_choice" -Data @{
                handle = $handleId
                choice = $selectedApprovalChoice
                choice_reason = $selectedApprovalChoiceReason
                scan_scope = [string]$approvalPrompt.ScanScope
                sent = $sent
                what_if = [bool]$WhatIfPreference
                input_method = $inputMethod
                error = $sendError
                prompt_context = [string]$approvalPrompt.Context
                approval_choice_count = $approvalChoicesSent
                approval_choice_attempts = $approvalChoiceAttempts
                session_id = $SessionId
            }

            if ($sent) {
                Write-Host "Sent Codex approval choice '$selectedApprovalChoice' ($selectedApprovalChoiceReason)."
            }
            elseif (-not [string]::IsNullOrWhiteSpace($sendError)) {
                Write-Host "Approval choice send failed and will retry after cooldown: $sendError"
            }
        }

        Start-Sleep -Milliseconds $PollMilliseconds
        continue
    }

    if ([bool]$interactivePromptBlock.Detected) {
        $clearSince = $null
        $blockReceiptClear = ((Get-Date) - $lastInteractivePromptBlockAt).TotalSeconds -ge 10
        if ($blockReceiptClear) {
            $interactivePromptBlocks += 1
            $lastInteractivePromptBlockAt = Get-Date
            Write-Receipt -Event "codex_live_continue.interactive_prompt_blocked" -Data @{
                handle = $handleId
                block_reason = [string]$interactivePromptBlock.BlockReason
                scan_scope = [string]$interactivePromptBlock.ScanScope
                title = [string]$status.Title
                prompt_context = [string]$interactivePromptBlock.Context
                prompt_block_count = $interactivePromptBlocks
                prompts_sent = $sentPrompts
                session_id = $SessionId
            }
            Write-Host "Paused Continuum because an interactive Codex prompt is visible; not sending '$Prompt'."
        }

        Start-Sleep -Milliseconds $PollMilliseconds
        continue
    }

    if (-not $DisableUsageLimitPause) {
        $now = [DateTimeOffset]::Now
        if ($null -ne $usagePausedUntil) {
            if ($now -lt $usagePausedUntil) {
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }

            Write-Receipt -Event "codex_live_continue.usage_resumed" -Data @{
                handle = $handleId
                pause_until = ([DateTimeOffset]$usagePausedUntil).ToString("o")
                reason = $usagePauseReason
                matched_text = $usagePauseMatchedText
                fallback_used = [bool]$usagePauseFallbackUsed
                prompts_sent = $sentPrompts
                session_id = $SessionId
            }
            Write-Host "Usage pause ended. Resumed Continuum watching."
            $usagePausedUntil = $null
            $usagePauseReason = ""
            $usagePauseMatchedText = ""
            $usagePauseFallbackUsed = $false
        }

        $usagePause = Get-UsagePauseState -Text ([string]$status.Text) -Now $now
        if ([bool]$usagePause.Detected -and $null -ne $usagePause.PauseUntil -and ([DateTimeOffset]$usagePause.PauseUntil) -gt $now) {
            $usagePausedUntil = [DateTimeOffset]$usagePause.PauseUntil
            $usagePauseReason = [string]$usagePause.Reason
            $usagePauseMatchedText = [string]$usagePause.MatchedText
            $usagePauseFallbackUsed = [bool]$usagePause.FallbackUsed
            $remainingSeconds = [int][Math]::Max(0, [Math]::Ceiling((([DateTimeOffset]$usagePausedUntil) - $now).TotalSeconds))

            Write-Receipt -Event "codex_live_continue.usage_paused" -Data @{
                handle = $handleId
                pause_until = ([DateTimeOffset]$usagePausedUntil).ToString("o")
                remaining_seconds = $remainingSeconds
                reason = $usagePauseReason
                matched_text = $usagePauseMatchedText
                fallback_used = [bool]$usagePauseFallbackUsed
                prompts_sent = $sentPrompts
                session_id = $SessionId
            }
            Write-Host "Paused Continuum because Codex reported a usage limit. Waiting until $(([DateTimeOffset]$usagePausedUntil).ToString("o"))."
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
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
                $consecutiveFailedSubmitAttempts = 0
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
                if (-not $WhatIfPreference) {
                    $consecutiveFailedSubmitAttempts += 1
                }
                $observedWorking = $false
                $clearSince = $null
            }
            else {
                $consecutiveFailedSubmitAttempts += 1
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
                consecutive_failed_submit_attempts = $consecutiveFailedSubmitAttempts
            }

            $staleWorkingIgnoreHash = ""
            $lastWorkingSnapshotHash = ""
            $workingSnapshotSince = $null

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

            if ($MaxFailedSubmitAttempts -gt 0 -and $consecutiveFailedSubmitAttempts -ge $MaxFailedSubmitAttempts) {
                $stopReason = "repeated_failed_submit"
                Write-Host "Stopped after $consecutiveFailedSubmitAttempts failed or unconfirmed submit attempt(s). Prompts sent: $sentPrompts"
                break
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
    consecutive_failed_submit_attempts = $consecutiveFailedSubmitAttempts
    approval_choices_sent = $approvalChoicesSent
    approval_choice_attempts = $approvalChoiceAttempts
    interactive_prompt_blocks = $interactivePromptBlocks
    session_id = $SessionId
}
}
