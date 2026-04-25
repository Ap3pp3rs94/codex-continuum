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

## It Finds The Wrong Window

List candidates:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Then run with `-TargetProcessId <pid>` instead of `-ProjectName`.

## It Never Sends

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
