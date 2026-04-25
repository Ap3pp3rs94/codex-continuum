# Usage

## Find Targets

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Use the displayed project title with `-ProjectName`, or use the exact PID with
`-TargetProcessId`.

## Run Until Ctrl+C

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -SessionId "<session-id>"
```

`-MaxPrompts 0` is the default and means unlimited.

## Bounded Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ProjectName "<ProjectName>" -MaxPrompts 3 -TimeoutSeconds 900
```

## Submit Confirmation

Continuum types `continue`, sends a submit key, then waits for the Codex status
to become `Working`.

Default submit confirmation window:

```powershell
-SubmitConfirmMilliseconds 3500
```

If your machine is slow to expose status changes through UI Automation, increase
that value.
