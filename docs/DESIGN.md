# Design

Codex Continuum is a live-window watcher.

## Flow

1. Resolve a live Codex PowerShell window by project name, PID, handle, or the
   only available candidate.
2. Read the bottom portion of the target window through Windows UI Automation
   and read the live PowerShell window title.
3. Watch for bottom `Working` text or the Codex spinner title, or treat the
   startup state as eligible if the session is already idle.
4. Wait until idle remains stable briefly.
5. Bring the same target window foreground.
6. Clear console selection mode with Escape, then type `continue`.
7. Submit and confirm the status returns to active work by text or title signal.
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

After each submit attempt, it waits for `Working` text or a Codex spinner title.
Receipts record the method and signal that confirmed, or record `unconfirmed` if
no method produced a visible status transition.

## Startup Idle Kick

Continuum defaults to sending once if it attaches to an already-idle session.
That handles the common case where the watcher starts after Codex has already
finished. After that first prompt, it goes back to requiring a new `Working` to
idle transition before sending again.
