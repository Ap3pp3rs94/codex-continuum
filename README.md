# Codex Continuum

Universal live-session continuation for Codex on Windows.

Codex Continuum watches one live Codex PowerShell window for live work signals:
the bottom `Working` text when UI Automation can see it, or the Codex spinner in
the window title when the terminal hides the bottom status. When work clears, it
types `continue` and submits it in the same window. It is built for the visible
session you are already using, not for hidden backend resume or archived
transcript replay.

## What It Does

- Targets any live Codex project window by `-ProjectName`, process id, or window
  handle.
- Sends input only to the selected live window.
- Types `continue`, submits it, and confirms Codex returns to active work by
  bottom status text or title spinner.
- Sends once on startup idle, so attaching after Codex has already finished
  still continues the session after a stable idle delay.
- Falls back across multiple submit keys if one Enter path types but does not
  submit.
- Retries foreground activation before typing, then keeps watching if Windows
  blocks one focus handoff.
- Pauses instead of continuing if Codex shows a usage-limit or rate-limit reset
  warning, then resumes after the reset time it can parse.
- Can opt in to selecting choice `1` on numbered Codex approval prompts, or
  choice `2` when the prompt says not to ask again, with an approval-choice
  receipt for audit. Approval detection scans the visible full-window tail only
  while Codex is not working.
- Fails closed on visible interactive prompts: if an approval-style prompt is
  suspected but not selected, Continuum writes an `interactive_prompt_blocked`
  receipt and does not type `continue` into the menu.
- Writes JSONL receipts for attach, status, prompt, and stop events.
- Provides `start`, `stop`, `status`, and `update` commands from one entrypoint.
- Runs until Ctrl+C by default.

## Quick Start

Start Continuum. It lists live Codex PowerShell windows, prompts for the target
PID, prompts for the session/thread id, then begins after you submit both
values:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start
```

List live Codex windows without starting:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Scripted starts can still pass the target and session id up front:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -TargetProcessId <pid> -SessionId "<session-id>"
```

Use `-NonInteractive` only for automation that intentionally wants the old
argument-only behavior:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -ProjectName "<ProjectName>" -SessionId "<session-id>" -NonInteractive
```

Probe before running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -ProbeOnly -VerboseStatusText
```

Stop it with Ctrl+C in the watcher PowerShell window.

If you do not want the startup idle kick, add
`-RequireObservedWorkingBeforeFirstPrompt`.

Continuum waits five continuous seconds after work clears before typing
`continue`; tune with `-StableClearMilliseconds` only when status detection is
reliably stable.

Check watcher health:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status
```

If a usage warning appears, Continuum records a `usage_paused` receipt and stops
sending `continue` until the reset time. If the warning does not include a time,
the default pause is one hour. Override with `-UsagePauseFallbackSeconds`, or
disable the guard with `-DisableUsageLimitPause`.

Auto-select approval prompts only when you intentionally want Continuum to pick
choice `1` on numbered Codex approval menus, or choice `2` when the prompt says
not to ask again:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -TargetProcessId <pid> -SessionId "<session-id>" -AutoSelectApprovalChoice
```

Stop running Continuum watchers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" stop
```

Update an installed release build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" update
```

## Install

From the latest GitHub release:

```powershell
$version = "0.2.1"
$zip = Join-Path $env:TEMP "codex-continuum-plugin-v$version.zip"
Invoke-WebRequest -Uri "https://github.com/Ap3pp3rs94/codex-continuum/releases/download/v$version/codex-continuum-plugin-v$version.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$env:USERPROFILE\.codex\plugins" -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\scripts\validate.ps1"
```

From a cloned repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Build a distributable plugin zip:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-plugin.ps1 -Force
```

Validate the package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

## Receipts

Receipts default to:

```text
%USERPROFILE%\.codex\plugins\codex-continuum\data\operator\codex-live-continue.jsonl
```

Runtime receipts are ignored by git.

Use the status command to turn those receipts into a health summary:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status -Json
```

## Boundaries

Codex Continuum is intentionally narrow. It does not call private Codex APIs,
does not read archived sessions, and does not claim background autonomy. It
drives the same local UI a human operator would use, with receipts.

More detail:

- [Usage](docs/USAGE.md)
- [Design](docs/DESIGN.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
