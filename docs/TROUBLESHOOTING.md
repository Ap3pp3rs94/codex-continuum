# Troubleshooting

## It Types But Does Not Send

Use the current build. It separates typing from submit and confirms that Codex
returns to `Working`.

Check the latest prompt receipt:

```powershell
Get-Content "$env:USERPROFILE\.codex\plugins\codex-continuum\data\operator\codex-live-continue.jsonl" -Tail 20
```

Look for `input_method`. A healthy submit usually ends with `-confirmed`.

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

If the captured text never contains `Working`, the terminal is not exposing the
status text through UI Automation. Try `-AllowFullWindowFallback` or target a
different terminal host.
