# Troubleshooting

## It Types But Does Not Send

Use the current build. It separates typing from submit and confirms that Codex
returns to `Working`.

If the target PowerShell title starts with `Select`, Windows console selection
mode is active and can swallow keystrokes. Continuum clears that mode with Escape
before typing.

Check the latest prompt receipt:

```powershell
Get-Content "$env:USERPROFILE\.codex\plugins\codex-continuum\data\operator\codex-live-continue.jsonl" -Tail 20
```

Look for `input_method`. A healthy submit usually ends with
`-confirmed-text` or `-confirmed-title`.

## target_window_not_foreground

Use the current build. Continuum now retries foreground activation with a Win32
thread-input handoff before typing. If Windows still blocks focus, the watcher
records `input_method:"send-failed"` with the error and retries after cooldown
instead of exiting.

## It Finds The Wrong Window

List candidates:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Then run with `-TargetProcessId <pid>` instead of `-ProjectName`.

## I Need To Stop It

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" stop
```

The stop command only targets Continuum watcher processes and records a
`codex_live_continue.stop_requested` receipt.

## It Paused For Usage

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status
```

If `State` is `UsagePaused`, Continuum saw a usage-limit or reset warning in the
live Codex window and intentionally stopped sending `continue`. The
`UsagePause` section shows `Until`, `RemainingSeconds`, `Reason`, and the
captured warning text. It resumes automatically after `Until`.

If the warning text is visible only outside the bottom terminal region, restart
with `-AllowFullWindowFallback` so Continuum can inspect the full window.

## Update Refuses To Run

The updater refuses to overwrite a git checkout. In a cloned repo, use:

```powershell
git pull
```

For a release-installed plugin, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" update
```

## It Never Sends

Run a status check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" status
```

If `State` is `IdleStale`, Continuum saw the target idle longer than the stale
threshold without a confirmed prompt. Check `Action`, `LastPrompt`, and
`Watcher.ProcessIds` in the report.

Run a probe:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -ProbeOnly -VerboseStatusText
```

Probe output includes `signal=text`, `signal=title`, or `signal=none`. If the
captured text never contains `Working`, Continuum can still use the Codex
spinner in the PowerShell title. If both signals are missing, try
`-AllowFullWindowFallback`, override `-TitleWorkingPattern`, or target a
different terminal host.

If the watcher attached while Codex was already idle, make sure you are on the
current build. The default now sends once on stable startup idle. Only pass
`-RequireObservedWorkingBeforeFirstPrompt` when you explicitly want to suppress
that first idle kick.
