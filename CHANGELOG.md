# Changelog

## 0.2.1

- Added usage-limit pause detection for live Codex reset warnings.
- Added `usage_paused` and `usage_resumed` receipts.
- Added status reporting for active usage pauses with remaining reset time.

## 0.2.0

- Added root entrypoint commands: `start`, `stop`, `status`, and `update`.
- Added `stop-continuum.ps1` for scoped watcher shutdown with stop-request
  receipts.
- Added `update-continuum.ps1` for release-zip updates with SHA256
  verification.

## 0.1.3

- Added a read-only `status` command that summarizes watcher health from JSONL
  receipts and live process metadata.
- Added stale-idle detection for cases where Continuum should have continued
  but did not.

## 0.1.2

- Match Codex title spinners after Windows title prefixes such as
  `Administrator:`.
- Treat a confirmed submit as an observed work cycle so the watcher catches the
  next idle completion even when title updates flicker.

## 0.1.1

- Added reproducible plugin zip packaging.
- Added GitHub release instructions and release workflow.
- Filled public repository metadata in the Codex plugin manifest.

## 0.1.0

- Fixed startup idle behavior so attaching after Codex has already finished
  sends one continuation prompt instead of waiting forever for a new `Working`
  transition.
- Clear Windows console selection mode before typing, because a `Select ...`
  PowerShell title can swallow both text and Enter.
- Detect active Codex work from the window-title spinner when the bottom
  `Working` text is not exposed by UI Automation.
- Harden foreground activation so the watcher can move focus back to the live
  Codex window before typing, and keep running if Windows blocks one attempt.
- Added universal `-ProjectName` targeting for live Codex PowerShell windows.
- Added process-id and window-handle targeting.
- Added confirmed submit behavior: after typing `continue`, Continuum submits
  and waits for Codex to return to `Working`.
- Added submit fallback order for terminals where one Enter path types but does
  not submit.
- Added JSONL receipts for attach, status, prompt, and stop events.
- Added install and validation scripts.
