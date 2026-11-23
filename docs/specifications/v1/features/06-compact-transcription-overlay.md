# Compact Transcription Overlay

**Status:** Complete

## Summary

Reduce the visual prominence of DictationApp's recording and transcription
overlay. Routine progress uses a content-fitting, single-line pill with concise
copy and symbol controls. States that require a decision retain a wider,
multi-line presentation with labeled actions.

Confirmed automatic insertion returns directly to Ready without showing a
visible success acknowledgement. A nonvisual accessibility announcement
preserves confirmation for users who cannot verify the inserted text by sight.

This specification supersedes the visible-success requirement in
`docs/specifications/v1/application.md`, the continuous overlay input-name
requirement in
`docs/specifications/v1/features/05-microphone-selection.md`, and the historical
fixed overlay dimensions and confirmed-success delay recorded in
`docs/plans/v1/progress.md`.

## Motivation

The current overlay is at least 500 points wide and 64 points high for routine
states. Its two-line content, generous padding, high-contrast border, and broad
shadow make ordinary progress more dominant than the information warrants.

A successful automatic insertion is already visible at the target text cursor.
The additional 1.2-second success overlay duplicates that confirmation and
delays the next recording.

The [interface polish specification](14-interface-polish.md) refines the
current recording and recovery visuals.

## Goals

- Make routine recording and transcription feedback smaller and quieter.
- Preserve the essential state, elapsed time, and direct session controls.
- Surface secondary information only when it requires attention.
- Remove visible feedback and delay after confirmed automatic insertion.
- Preserve clear, labeled recovery actions when user intervention is required.
- Preserve non-activation, insertion-target ownership, accessibility, and
  multi-display behavior.

## Non-goals

- Change recording, transcription, post-processing, insertion, or clipboard
  semantics other than the confirmed-success presentation delay.
- Change menu-bar information or actions.
- Change overlay placement or introduce user-configurable overlay appearance.
- Add animation, input-level metering, microphone preview, or new sound cues.
- Shorten existing no-speech, raw-fallback, unverified-insertion,
  clipboard-fallback, too-short, or capture-failure presentation durations.
- Add an automated test target.

## Presentation model

The overlay has two presentation modes.

### Compact mode

Use compact mode for routine progress and non-actionable transient outcomes:

- Preparing
- Recording
- Finalizing
- Transcribing
- Post-processing
- Inserting
- Raw-transcript fallback after confirmed insertion
- No speech
- Recording too short
- Completed and cancelled compatibility states if they are presented

Compact mode must:

- Use one horizontal line containing a state indicator, concise status, and any
  applicable controls.
- Fit its content instead of reserving one shared fixed width.
- Remain no more than approximately 360 points wide and 44 points high under
  standard macOS display and text settings.
- Permit additional space when required by macOS accessibility settings.
- Use compact spacing and padding, a subtle capsule border, and a materially
  softer shadow than the current overlay.
- Retain the material capsule identity.
- Change state and size without transition or window animation.

The ordinary compact copy is:

- `Starting…`
- `Recording 0:12`
- `Finalizing…`
- `Transcribing…`
- `Cleaning up…`
- `Inserting…`
- `No speech detected`
- `Recording too short`

Preparing remains visible immediately after the shortcut is accepted, even
when preparation completes quickly.

### Attention mode

Use attention mode when the message or controls determine the user's next
action:

- Recoverable capture failure
- Transcription failure
- Unverified insertion
- Clipboard fallback
- Other failures with actionable or materially explanatory copy

Attention mode must:

- Retain multi-line title and detail content.
- Retain labeled Settings, Retry, Discard, Transcribe Partial, and Dismiss
  actions where currently applicable.
- Fit content within an approximately 440-to-520-point range instead of using
  the current 600-to-640-point fixed widths.
- Preserve full instructions when the user must make a decision.
- Use the quieter border, spacing, and shadow treatment shared with compact
  mode without forcing attention content into compact-mode dimensions.

## Recording presentation

The ordinary recording pill shows:

- A red recording indicator.
- Elapsed time.
- A symbol-only Stop button using a filled square.
- A symbol-only Cancel button using an `xmark`.

The overlay omits the routine input-device name. The menu-bar status continues
to show the actual device name throughout recording.

When the preferred microphone is unavailable, the recording pill replaces
ordinary secondary information with a concise fallback warning and the actual
fallback device name. A long visual device name may truncate to preserve the
compact bound, but its accessibility value and the menu-bar status must remain
complete.

When the recording approaches its duration limit, the pill shows concise
single-line copy such as `Recording 9:31 · Limit soon`. Warning text and symbols
must make the condition understandable without relying on color alone.

Symbol controls must preserve their existing actions and roles, remain
pointer-operable without activating DictationApp, expose complete accessibility
labels, and provide concise hover help.

## Processing presentation

Routine processing pills show only their primary message and Cancel control.
They do not show provider names or upload/cleanup explanations. The menu-bar UI
continues to expose the fuller provider-specific status.

The raw-transcript fallback remains visible for the existing 2.5-second
period. It uses the classified compact message in the
[cleanup fallback feedback specification](15-cleanup-fallback-feedback.md).
Detailed fallback information remains available in the menu-bar status.

## Confirmed insertion

After confirmed automatic insertion:

- Restore the previous clipboard snapshot when DictationApp still owns the
  clipboard transaction.
- Do not show a checkmark, success pill, or other visible confirmation.
- Do not wait for the historical 1.2-second success-display interval.
- Return directly to idle and publish Ready presentation.
- Accept a new recording shortcut immediately.
- Post a nonvisual accessibility announcement: `Transcript inserted`.

The internal inserted transition may remain as an implementation boundary, but
it must not produce visible UI or delay return to idle.

## Preserved behavior

- Position the panel at the bottom center of the display selected when the
  session begins.
- Keep the panel non-activating and prevent it from becoming key or main.
- Do not move or replace the focused insertion target.
- Keep Cancel available until insertion completes.
- Preserve Stop, Retry, Discard, Settings, Transcribe Partial, and Dismiss
  semantics.
- Preserve existing transient and recovery-state durations except for the
  removed confirmed-success delay.
- Preserve complete menu-bar status and recovery controls.
- Preserve state announcements and ensure status and failure information does
  not rely on color alone.

## Acceptance criteria

- No routine state retains the current 500-point minimum width or 64-point
  minimum height.
- Routine and non-actionable transient states use the compact, single-line
  presentation within the target bounds under standard macOS settings.
- Routine recording omits the input name; microphone fallback identifies the
  actual fallback input without forcing an ordinary two-line layout.
- Routine processing omits provider-specific detail from the overlay while the
  menu retains it.
- Symbol Stop and Cancel controls are discoverable through visuals, hover help,
  and accessibility labels.
- Confirmed insertion produces no visible success UI, returns immediately to
  Ready, accepts another shortcut, and posts the accessibility announcement.
- Raw-transcript fallback remains visibly distinct from ordinary confirmed
  insertion.
- Attention states retain complete guidance and labeled actions within their
  wider bounded layout.
- The overlay remains non-activating, focus-safe, pointer-operable, accessible,
  and anchored to the session display.
- Debug and Release builds succeed, and repository whitespace and privacy
  checks pass.
