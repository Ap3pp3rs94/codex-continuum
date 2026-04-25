# Changelog

## 0.1.0

- Added universal `-ProjectName` targeting for live Codex PowerShell windows.
- Added process-id and window-handle targeting.
- Added confirmed submit behavior: after typing `continue`, Continuum submits
  and waits for Codex to return to `Working`.
- Added submit fallback order for terminals where one Enter path types but does
  not submit.
- Added JSONL receipts for attach, status, prompt, and stop events.
- Added install and validation scripts.
