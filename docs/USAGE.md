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

## Usage-Limit Pause

Continuum watches the captured live-session text for Codex usage-limit,
rate-limit, quota, and reset warnings. When it sees one, it stops sending
`continue`, writes a `codex_live_continue.usage_paused` receipt, and waits until
the reset time it can parse. It recognizes relative warnings such as
`try again in 30 minutes`, clock warnings such as `resets at 3:00 PM`, and ISO
timestamps.

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
counts, and stale idle conditions.

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
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" update -Version 0.2.1
```

If you are inside a git checkout, use `git pull` instead. The updater refuses
to overwrite a git checkout unless you pass `-Force`.

## Submit Confirmation

Continuum types `continue`, sends a submit key, then waits for Codex to become
active again. It checks both the bottom `Working` status text and the spinner
prefix that Codex puts in the PowerShell window title.

Default submit confirmation window:

```powershell
-SubmitConfirmMilliseconds 3500
```

If your machine is slow to expose status changes through UI Automation, increase
that value.

If your terminal title does not use the default Codex spinner prefix, override
`-TitleWorkingPattern`.

## Downloadable Plugin Install

Download the release zip into the Codex plugin folder:

```powershell
$version = "0.2.1"
$zip = Join-Path $env:TEMP "codex-continuum-plugin-v$version.zip"
Invoke-WebRequest -Uri "https://github.com/Ap3pp3rs94/codex-continuum/releases/download/v$version/codex-continuum-plugin-v$version.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$env:USERPROFILE\.codex\plugins" -Force
```

Then run Continuum from:

```powershell
$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1
```
