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
- Writes JSONL receipts for attach, status, prompt, and stop events.
- Runs until Ctrl+C by default.

## Quick Start

List live Codex windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Start Continuum for any project name shown in the Codex window title:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -SessionId "<session-id>"
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

## Install

From this repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
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

## Boundaries

Codex Continuum is intentionally narrow. It does not call private Codex APIs,
does not read archived sessions, and does not claim background autonomy. It
drives the same local UI a human operator would use, with receipts.

More detail:

- [Usage](docs/USAGE.md)
- [Design](docs/DESIGN.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
