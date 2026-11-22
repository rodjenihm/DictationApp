# Dictation Pipeline Latency

**Status** · Implemented, live latency verification pending

## Goal

Reduce the time from shortcut activation to usable audio and from Stop to
text insertion. Keep the app responsive while capture, transcription,
cleanup, and delivery are in progress.

The [recording startup specification](04-recording-startup-performance.md)
defines the 200 ms warm built-in-microphone target from accepted start to
first owned audio buffer. This feature extends measurement to the complete
workflow and keeps that existing target.

## Measurement

Use a monotonic clock and correlate timing events within a session. Measure
these boundaries for the existing completed-file paths:

| Interval | Boundaries |
| --- | --- |
| Shortcut and capture | Shortcut callback, accepted start, first writer-accepted buffer, and published recording state |
| Stop and finalization | Stop action, microphone stop, writer close, and validated artifact |
| Transcription | Request preparation, each provider attempt and retry wait, and final raw transcript |
| Optional cleanup | Stage start, attempts and retry waits, and validated result or raw fallback |
| Delivery | Clipboard snapshot and write, Accessibility target preparation, Cmd+V dispatch, verification outcome, and readiness for the next session |

Cmd+V dispatch is an app-side milestone. Use positive target readback or
direct observation to establish when text appears. Report verified and
unverified outcomes separately. The spoken portion of a recording is
excluded from the Stop-to-paste interval.

Record median and p95 with sample counts for short and long recordings,
cold and repeated starts, supported providers, and cleanup enabled and
disabled. Compare before and after on the same hardware, audio input, target
editor, and provider settings. Use a separate comparison for Bluetooth or a
different microphone route. Record success, fallback, and cancellation
counts alongside the timings.

Keep diagnostics local. Log durations, stage names, attempt counts, and
outcome classifications. Exclude dictated text, target text, audio, clipboard
data, credentials, paths, and persistent device or target identifiers.

### Capture startup detail

Separate device discovery, recording directory setup, recorder queue wait,
audio unit configuration, writer setup, audio unit initialization, the
return to the main actor, and device observer installation. Keep the existing
aggregate preparation and first-buffer timings for comparison. Measure once
per relevant setup step and candidate, outside the real-time audio callback.
Record the time between accepted start and recorder preparation separately.

## Local responsiveness

- Publish recording presentation updates when the displayed second or
  duration warning changes. Preserve monotonic automatic stop and timely
  delivery of Stop, Cancel, and capture-failure events.
- Keep recording readiness tied to the first writer-accepted buffer. Keep the
  microphone inactive between sessions and continue to resolve the current
  input according to the [microphone selection specification](05-microphone-selection.md).
- Prepare the initial overlay view and layout after launch while it is
  hidden. Resolve the target display and show the panel when a dictation
  begins. The overlay must remain non-activating and ready to show if the
  first dictation starts before preparation finishes.
- Signal readiness with the start cue after the first owned buffer. Keep
  sound loading and playback off the shortcut-to-capture path.
- Apply the explicit Accessibility timeout required by the
  [runtime robustness specification](02-runtime-robustness-improvements.md#5-bounded-accessibility-messaging).
  End target probing on a messaging timeout. Limit optional editor-tree
  inspection so a large tree cannot indefinitely delay paste.
- Resolve focus at delivery time. Preserve boundary spacing, selection
  replacement, single-paste delivery, and clipboard ownership safeguards.
  Before dispatch, use the manual-paste fallback if the target cannot be
  reached. After dispatch, use Unverified if confirmation is unavailable.
- Accept each confirmation signal permitted by the
  [application specification](../application.md#text-insertion-behavior).
  Keep the paste payload available through the consumption window. Measure
  verification and restoration independently of paste dispatch.

## Cleanup responsiveness

Cleanup runs after a usable raw transcript exists. Give it a wall-clock
budget that includes request time and retry waits. Use the raw transcript
when the budget expires, preserve the user's cleanup selection, and prevent
late responses from changing the chosen result. A retry may start only if
it can respect both the provider's retry delay and the remaining budget.
The initial budget is four seconds plus one second per full 500 UTF-8 bytes
of raw text, capped at twelve seconds. The budget includes provider
preparation and output validation. At expiry, request cancellation and allow
raw delivery to proceed independently of provider teardown. Read runtime
OpenAI credentials off the main actor at the existing request boundary.
The budget is an initial responsiveness policy
chosen without live provider timing. Use timing and raw-fallback rates to
tune it after collecting representative samples. Preserve permanent
configuration-failure handling and transcription retry behavior.

When raw fallback text is confirmed, make the next dictation
available immediately. Show the raw-fallback status during the existing
display interval, unless a new dictation starts.

## Transcription follow-up

Completed-file transcription remains the comparison baseline. The
[live Apple On-Device specification](11-live-apple-transcription.md)
defines concurrent local analysis and the conditions for file fallback.
Any future live cloud mode requires a separate specification for consent,
audio transfer before Stop, cancellation, and reconnect or retained-recording
recovery.

## Acceptance

- The timing record identifies the critical path for each provider and
  distinguishes dispatch, verified delivery, and readiness for reuse.
- Recording updates occur at displayed-second granularity aside from
  meaningful state changes. Stop and the automatic limit remain responsive.
- An Accessibility messaging failure reaches the appropriate clipboard
  fallback without retrying paste or overwriting a newer clipboard.
- Cleanup respects its documented budget and delivers usable raw text if
  the budget expires.
- Any latency improvement claim includes before-and-after measurements and
  notes any change in delivery outcomes.
