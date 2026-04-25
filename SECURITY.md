# Security

Codex Continuum is local UI automation. It can type into a selected window, so
targeting correctness matters.

## Supported Boundary

- Windows only.
- Live Codex PowerShell windows only.
- Local operator-controlled sessions only.

## Reporting

For local use, record:

- exact command used,
- target PID or project name,
- receipt tail from `data/operator/codex-live-continue.jsonl`,
- whether the wrong window received input.

Do not include secrets or private transcript content in public reports.
