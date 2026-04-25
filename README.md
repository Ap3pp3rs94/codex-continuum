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
  still continues the session.
- Falls back across multiple submit keys if one Enter path types but does not
  submit.
- Retries foreground activation before typing, then keeps watching if Windows
  blocks one focus handoff.
- Pauses instead of continuing if Codex shows a usage-limit or rate-limit reset
  warning, then resumes after the reset time it can parse.
- Writes JSONL receipts for attach, status, prompt, and stop events.
- Provides `start`, `stop`, `status`, and `update` commands from one entrypoint.
- Runs until Ctrl+C by default.

## Quick Start

List live Codex windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Start Continuum for any project name shown in the Codex window title:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -ProjectName "<ProjectName>" -SessionId "<session-id>"
```

Start by PID when multiple windows have similar titles:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -TargetProcessId <pid> -SessionId "<session-id>"
```

Probe before running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -ProbeOnly -VerboseStatusText
```

Stop it with Ctrl+C in the watcher PowerShell window.

If you do not want the startup idle kick, add
`-RequireObservedWorkingBeforeFirstPrompt`.

Check watcher health:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status
```

If a usage warning appears, Continuum records a `usage_paused` receipt and stops
sending `continue` until the reset time. If the warning does not include a time,
the default pause is one hour. Override with `-UsagePauseFallbackSeconds`, or
disable the guard with `-DisableUsageLimitPause`.

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
