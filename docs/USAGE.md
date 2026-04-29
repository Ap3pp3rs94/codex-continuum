# Usage

## Find Targets

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

The default `start` command also lists live Codex windows before it attaches.
Continuum prompts for the visible Codex PowerShell PID and the session/thread id
and begins only after both values are submitted:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start
```

If you paste a child Codex PID, Continuum resolves it back to the owning visible
Codex PowerShell window when that process is still alive.

If the PID is not visible to `Get-Process` or `Win32_Process`, Continuum cannot
attach to it. Use one of the visible candidates instead.

## Run Until Ctrl+C

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -TargetProcessId <pid> -SessionId "<session-id>"
```

`-MaxPrompts 0` is the default and means unlimited.

Use `-NonInteractive` for automation that must not prompt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -ProjectName "<ProjectName>" -SessionId "<session-id>" -NonInteractive
```

By default, Continuum also sends one prompt if the selected live session is
already idle when the watcher starts. Use `-RequireObservedWorkingBeforeFirstPrompt`
to wait for a fresh `Working` state before the first continuation.

Continuum waits for five continuous seconds of idle state before it types
`continue`. Override only if your terminal exposes reliable status changes:

```powershell
-StableClearMilliseconds 5000
```

Continuum stops after three failed or unconfirmed submit attempts by default:

```powershell
-MaxFailedSubmitAttempts 3
```

Set `-MaxFailedSubmitAttempts 0` only when you want to disable that stop guard.

## Stuck-Working Resync

Continuum tracks a fingerprint of the visible working snapshot: title, working
signal, visible text, accessible element count, and fallback mode. If that
fingerprint does not change for 30 minutes while the session still appears to be
working, Continuum writes a `codex_live_continue.resynced` receipt and refreshes
the attached handle from the configured target PID or window handle.

Default threshold:

```powershell
-StuckWorkingSeconds 1800
```

Default resync cooldown:

```powershell
-ResyncCooldownSeconds 300
```

Set `-StuckWorkingSeconds 0` to disable stuck-working resync. If the stuck
signal is only bottom `Working` or `Waiting for background...` text and the
window title is no longer actively working, Continuum treats the stale text as
idle long enough for the normal stable-idle and full-window interactive prompt
guards to run. It does not bypass approval blocking.

## Guarded Approval-Safe Run

This is the recommended form when you want Continuum to handle Codex numbered
approval prompts and never type `continue` into a menu:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -TargetProcessId <visible-pwsh-pid> -SessionId "<session-id>" -StatusPattern '(?!)' -StableClearMilliseconds 5000 -AutoSelectApprovalChoice -ApprovalChoice 1 -DoNotAskAgainApprovalChoice 2 -RequireObservedWorkingBeforeFirstPrompt
```

Use this mode when bottom `Working` text is stale or unreliable. The
`-StatusPattern '(?!)'` argument disables bottom `Working` matching for the run,
so work detection relies on the Codex title spinner plus the separate background
wait matcher.

## Usage-Limit Pause

Continuum watches the captured live-session text for actionable Codex
usage-limit, rate-limit, and reset warnings. Generic transcript or repository
text that only mentions quota is ignored. When Continuum sees an actionable
warning, it stops sending `continue`, writes a
`codex_live_continue.usage_paused` receipt, and waits until the reset time it can
parse. It recognizes relative warnings such as `try again in 30 minutes`, clock
warnings such as `resets at 3:00 PM`, and ISO timestamps.

If a warning does not include a reset time, Continuum pauses for one hour by
default:

```powershell
-UsagePauseFallbackSeconds 3600
```

Set a different fallback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -ProjectName "<ProjectName>" -UsagePauseFallbackSeconds 7200
```

Disable the guard only when you explicitly want Continuum to keep trying through
usage warnings:

```powershell
-DisableUsageLimitPause
```

## Stop And Pause Conditions

Continuum distinguishes stop conditions from temporary pauses:

- Actionable usage-limit, rate-limit, and reset warnings write
  `codex_live_continue.usage_paused` and pause sends until the parsed reset time
  or fallback pause expires.
- Visible interactive prompts write
  `codex_live_continue.interactive_prompt_blocked` and block `continue` until
  the prompt clears or a safe approval choice is sent.
- Stuck working snapshots write `codex_live_continue.resynced` and refresh the
  live target attachment before any stale text is treated as idle.
- Closed target windows stop the watcher with `window_closed`.
- `-ExitOnFocusLoss` stops the watcher with `focus_lost`; without that flag,
  focus loss is not a hard stop.
- Repeated failed or unconfirmed submits stop the watcher with
  `repeated_failed_submit`.
- Creating the kill flag stops the watcher with `kill_flag`.
- `-TimeoutSeconds` and `-MaxPrompts` stop bounded runs with `timeout` or
  `max_prompts`.

Default kill flag:

```text
%USERPROFILE%\.codex\plugins\codex-continuum\data\operator\codex-live-continue.kill
```

Override it when a run needs a scoped stop file:

```powershell
-KillFlagPath "C:\Temp\codex-continuum.stop"
```

## Approval Choice Automation

When explicitly enabled and Codex is not currently working, Continuum scans the
visible live-session window for a numbered Codex approval-style menu. It sends
choice `1` followed by Enter by default, but sends choice `2` when the prompt
text includes "do not ask again" or an equivalent no-ask-again phrase. The
default matcher requires at least two numbered choices plus approval or
permission language, and every selection writes a
`codex_live_continue.approval_choice` receipt with the scan scope.
Codex command prompts such as "Would you like to run the following command?"
match this approval path.

If the visible session still looks like an interactive Codex prompt but the
approval selector does not send a choice, Continuum fails closed: it writes a
`codex_live_continue.interactive_prompt_blocked` receipt and does not type
`continue` into the prompt. This also protects prompt menus when approval
selection is disabled.

When the terminal title enters a `Select ...` state, Continuum treats that as
Windows console selection mode, clears it with Escape, and writes a
`codex_live_continue.selection_mode_cleared` receipt. Approval menus are blocked
only when readable prompt text shows an actual command or numbered prompt.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -TargetProcessId <pid> -SessionId "<session-id>" -AutoSelectApprovalChoice
```

The default selected choice is `1`, and the no-ask-again selected choice is `2`.
Override only when Codex changes its menu:

```powershell
-ApprovalChoice 1 -DoNotAskAgainApprovalChoice 2
```

## Bounded Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -MaxPrompts 3 -TimeoutSeconds 900
```

## Status

Read the watcher health summary:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status
```

Machine-readable status:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status -Json
```

The status report is read-only. It summarizes receipts, watcher processes, the
target process, last working signal, last prompt, last approval choice, prompt
counts, interactive prompt blocks, usage pauses, resyncs, and stale idle
conditions.

## Stop

Stop running Continuum watchers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" stop
```

Stop the watcher for one target PID:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" stop -TargetProcessId <pid>
```

## Update

Update an installed release build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" update
```

Update to a specific release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" update -Version 0.2.3
```

If you are inside a git checkout, use `git pull` instead. The updater refuses
to overwrite a git checkout unless you pass `-Force`.

## Submit Confirmation

Continuum types `continue`, sends a submit key, then waits for Codex to become
active again. It checks bottom `Working` status text, bottom `Waiting for
background...` text, and the spinner prefix that Codex puts in the PowerShell
window title.

Default submit confirmation window:

```powershell
-SubmitConfirmMilliseconds 3500
```

If your machine is slow to expose status changes through UI Automation, increase
that value.

If your terminal title does not use the default Codex spinner prefix, override
`-TitleWorkingPattern`.

If Codex changes the background-wait wording, override `-BackgroundWaitPattern`.

## Downloadable Plugin Install

Download the release zip into the Codex plugin folder:

```powershell
$version = "0.2.3"
$zip = Join-Path $env:TEMP "codex-continuum-plugin-v$version.zip"
Invoke-WebRequest -Uri "https://github.com/Ap3pp3rs94/codex-continuum/releases/download/v$version/codex-continuum-plugin-v$version.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$env:USERPROFILE\.codex\plugins" -Force
```

Then run Continuum from:

```powershell
$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1
```
