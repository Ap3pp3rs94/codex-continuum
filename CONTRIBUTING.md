# Contributing

Codex Continuum is deliberately small. Keep changes focused on live-session
continuation and operator safety.

## Rules

- Do not add hidden backend resume behavior.
- Do not send input to a window that was not explicitly selected.
- Keep receipt events truthful and machine-readable.
- Prefer additive validation over broad rewrites.
- Preserve Ctrl+C as the stop path.

## Validate

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

If Pester is installed, the validation script also runs `tests/*.Tests.ps1`.
