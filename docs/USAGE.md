# Usage

## Find Targets

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" -ListCandidates
```

Use the displayed project title with `-ProjectName`, or use the exact PID with
`-TargetProcessId`.

## Run Until Ctrl+C

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" start -ProjectName "<ProjectName>" -SessionId "<session-id>"
```

`-MaxPrompts 0` is the default and means unlimited.

By default, Continuum also sends one prompt if the selected live session is
already idle when the watcher starts. Use `-RequireObservedWorkingBeforeFirstPrompt`
to wait for a fresh `Working` state before the first continuation.

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
target process, last working signal, last prompt, prompt counts, and stale idle
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
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1" update -Version 0.2.0
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
$version = "0.2.0"
$zip = Join-Path $env:TEMP "codex-continuum-plugin-v$version.zip"
Invoke-WebRequest -Uri "https://github.com/Ap3pp3rs94/codex-continuum/releases/download/v$version/codex-continuum-plugin-v$version.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$env:USERPROFILE\.codex\plugins" -Force
```

Then run Continuum from:

```powershell
$env:USERPROFILE\.codex\plugins\codex-continuum\codex-continuum.ps1
```
