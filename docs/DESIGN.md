# Design

Codex Continuum is a live-window watcher.

## Flow

1. Resolve a live Codex PowerShell window by project name, PID, handle, or the
   only available candidate.
2. Read the bottom portion of the target window through Windows UI Automation.
3. Watch for `Working`.
4. Wait until `Working` clears and remains clear briefly.
5. Bring the same target window foreground.
6. Type `continue`.
7. Submit and confirm the status returns to `Working`.
8. Write a receipt.

## Why UI Automation

The visible Codex TUI is the source of truth for this package. Backend resume or
session logs can prove a session exists, but they do not continue the currently
focused chat. Continuum acts on the live operator surface.

## Submit Fallback

Some terminals accept typed text but ignore one Enter path. Continuum separates
text entry from submit and tries:

```text
SendKeys "~"
SendKeys "^m"
SendInput VK_RETURN
SendKeys "{ENTER}"
```

After each submit attempt, it waits for `Working`. Receipts record the method
that confirmed, or record `unconfirmed` if no method produced a visible status
transition.
