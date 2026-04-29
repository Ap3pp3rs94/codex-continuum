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
5. Watch for bottom `Working` text, `Waiting for background...` text, or the
   Codex spinner title, or treat the startup state as eligible if the session is
   already idle.
6. Wait until idle remains stable for five seconds.
7. Bring the same target window foreground with a Win32 activation retry path.
8. Clear console selection mode with Escape, then type `continue`.
9. Submit and confirm the status returns to active work by text or title signal.
10. Stop after repeated failed or unconfirmed submit attempts.
11. Write a receipt.

## Why UI Automation

The visible Codex TUI is the source of truth for this package. Backend resume or
session logs can prove a session exists, but they do not continue the currently
focused chat. Continuum acts on the live operator surface.

## Why Not Background Autonomy

Continuum does not own a work queue, mutate files directly, or decide what work
Codex should do next. It uses the same visible session a human operator selected
and only sends the configured continuation prompt or bounded approval choice.
That keeps the trust boundary local and inspectable: when the target window is
gone, the prompt is ambiguous, the usage limit is active, or submit confirmation
fails repeatedly, the watcher stops or pauses and writes receipts.

## Submit Fallback

Some terminals accept typed text but ignore one Enter path. Continuum separates
text entry from submit and tries:

```text
SendKeys "~"
SendKeys "^m"
SendInput VK_RETURN
SendKeys "{ENTER}"
```

After each submit attempt, it waits for `Working` text, `Waiting for
background...` text, or a Codex spinner title. Receipts record the method and
signal that confirmed, or record `unconfirmed` if no method produced a visible
status transition.

Unconfirmed submit attempts increment `consecutive_failed_submit_attempts`. The
watcher stops with `repeated_failed_submit` when the count reaches
`-MaxFailedSubmitAttempts` unless that setting is `0`.

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

The same idle scan has a fail-closed path. If the visible window text looks like
an interactive Codex prompt and no approval choice is sent, the watcher writes
`codex_live_continue.interactive_prompt_blocked` and skips the normal
`continue` branch for that poll. A `Select ...` title by itself is handled as
Windows console selection mode: the watcher clears it with Escape and writes
`codex_live_continue.selection_mode_cleared` before scanning again. This keeps
unrecognized menus from receiving free-form continuation text without freezing
on console selection mode.

Status treats a prompt block as active only while the target is idle and no
newer attach, prompt, approval choice, or stop receipt has superseded it. That
keeps old prompt-block receipts available for audit without leaving status stuck
in a paused state after the operator clears the menu or restarts the watcher.

## Stop And Pause Conditions

Hard stops:

- `window_closed`: the attached live window no longer exists.
- `focus_lost`: focus left the target and `-ExitOnFocusLoss` was set.
- `repeated_failed_submit`: failed or unconfirmed submits reached the configured
  threshold.
- `kill_flag`: the configured kill-flag file exists.
- `timeout` / `max_prompts`: bounded run limit reached.
- `ctrl_c_or_process_exit`: operator interrupted the watcher or the host exited.

Pauses:

- `usage_paused`: an actionable usage-limit, rate-limit, or reset warning was
  detected.
- `interactive_prompt_blocked`: a visible prompt looked interactive but was not
  safely selectable.
- `focus_lost` with `-PauseWhenTargetNotForeground`: focus left the target and
  the run was configured to pause rather than continue in the background.

## Guarded Title-Signal Runs

Some Codex terminals leave stale bottom `Working` text visible after the session
has stopped. For those windows, use `-StatusPattern '(?!)'` to disable
bottom-status matching and rely on the Codex spinner in the PowerShell title.
Pair it with `-RequireObservedWorkingBeforeFirstPrompt` when restarting around
an existing prompt, so Continuum waits for a fresh work cycle before sending the
first `continue`.

The default text status pattern is line-anchored and case-sensitive so transcript
output such as `working copy` does not count as Codex's live `Working` status.
Background waits are a separate active signal and receipt as
`working_signal:"background_wait"`, so the watcher waits instead of typing
`continue` while Codex is waiting on a background task.

## Startup Intake

The launcher treats the visible PowerShell window as the attachment boundary.
When a start command does not pass a target PID or session id, it lists live
Codex PowerShell windows and requires the operator to submit both values before
the watcher starts. `-NonInteractive` preserves argument-only behavior for
scheduled or scripted use.
