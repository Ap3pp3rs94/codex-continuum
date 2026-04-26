# Design

Codex Continuum is a live-window watcher.

## Flow

1. Prompt for the visible Codex PowerShell PID and session/thread id unless
   those values were passed explicitly, then resolve the PID to the owning live
   Codex PowerShell window.
2. Read the bottom portion of the target window through Windows UI Automation
   and read the live PowerShell window title.
3. If enabled, detect numbered Codex approval menus and send the configured
   choice with a receipt.
4. If an interactive prompt is visible but no approval choice was sent, write a
   block receipt and skip continuation for that poll.
5. Watch for bottom `Working` text or the Codex spinner title, or treat the
   startup state as eligible if the session is already idle.
6. Wait until idle remains stable for five seconds.
7. Bring the same target window foreground with a Win32 activation retry path.
8. Clear console selection mode with Escape, then type `continue`.
9. Submit and confirm the status returns to active work by text or title signal.
10. Write a receipt.

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

## Foreground Activation

Windows can reject a plain `SetForegroundWindow` call when the watcher
PowerShell is foreground. Continuum restores the target window, temporarily
attaches input threads, sends a harmless Alt key unlock, and retries activation
before typing. If Windows still blocks the handoff, the watcher records the
failed send attempt and keeps running instead of exiting.

## Startup Idle Kick

Continuum defaults to sending once if it attaches to an already-idle session.
That handles the common case where the watcher starts after Codex has already
finished. It still waits for the same five-second stable idle window before
sending. After that first prompt, it goes back to requiring a new `Working` to
idle transition before sending again.

## Approval Choice Automation

Approval choice automation is opt-in because it crosses a permission boundary.
When `-AutoSelectApprovalChoice` is set and Codex is not currently working,
Continuum scans the visible full-window tail for at least two numbered choices
and approval-related text before it sends the configured `-ApprovalChoice`. If
the prompt includes a no-ask-again phrase, it sends the configured
`-DoNotAskAgainApprovalChoice` instead. It does not clear the prompt with Escape
before sending the choice. Each send writes a
`codex_live_continue.approval_choice` receipt with `choice_reason` and
`scan_scope`.

The same idle scan has a fail-closed path. If the visible window looks like an
interactive Codex prompt, or the title enters a `Select ...` state, and no
approval choice is sent, the watcher writes
`codex_live_continue.interactive_prompt_blocked` and skips the normal
`continue` branch for that poll. This keeps unrecognized menus from receiving
free-form continuation text.

Status treats a prompt block as active only while the target is idle and no
newer attach, prompt, approval choice, or stop receipt has superseded it. That
keeps old prompt-block receipts available for audit without leaving status stuck
in a paused state after the operator clears the menu or restarts the watcher.

## Guarded Title-Signal Runs

Some Codex terminals leave stale bottom `Working` text visible after the session
has stopped. For those windows, use `-StatusPattern '(?!)'` to disable
bottom-status matching and rely on the Codex spinner in the PowerShell title.
Pair it with `-RequireObservedWorkingBeforeFirstPrompt` when restarting around
an existing prompt, so Continuum waits for a fresh work cycle before sending the
first `continue`.

## Startup Intake

The launcher treats the visible PowerShell window as the attachment boundary.
When a start command does not pass a target PID or session id, it lists live
Codex PowerShell windows and requires the operator to submit both values before
the watcher starts. `-NonInteractive` preserves argument-only behavior for
scheduled or scripted use.
