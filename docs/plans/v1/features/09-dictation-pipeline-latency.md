# Dictation Pipeline Latency Implementation Plan

**Status** · Implemented, live latency verification pending

**Specification** · [Dictation Pipeline Latency](../../../specifications/v1/features/09-dictation-pipeline-latency.md)

## Review baseline

The November 22, 2026 source review covers revision `e2bc125`. The most
recent capture measurements found in the repository are from
[August 2, 2026](05-microphone-selection.md#verification-evidence).
The built-in input reached the first buffer in 42–45 ms and the recording
state in 110–186 ms. A local stop finalized in 28 ms. Those observations
cover capture only. The host's recent unified log had no matching capture
timings, so the current performance ranking is based on source inspection.

Unsigned macOS Debug and Release baseline builds passed with Xcode 27.2.
Xcode reported host device-support and simulator framework warnings. This
review made only documentation changes and did not run live dictation.

| Priority | Finding | Evidence and proposed action |
| --- | --- | --- |
| Highest potential Stop-to-paste gain | Both providers wait for a finalized M4A | [Coordinator](../../../../DictationApp/Engine/DictationCoordinator.swift#L468) and [Apple Speech](../../../../DictationApp/Infrastructure/AppleSpeech/AppleSpeechService.swift#L228). Apple resolves locale, checks assets, and opens the file before it starts analysis. Measure analyzer preparation during recording, then evaluate live local PCM analysis with a separate spec. |
| High tail latency | Optional cleanup is a serial network request with up to three attempts | [Delivery](../../../../DictationApp/Engine/DictationCoordinator.swift#L884), [cleanup timeouts](../../../../DictationApp/Infrastructure/OpenAI/OpenAIPostProcessingProvider.swift#L75), and [retry policy](../../../../DictationApp/Engine/Providers/RetryExecutor.swift#L15). Three 60-second attempts and up to 30 seconds of retry waiting can hold usable raw text for about 210 seconds under failure. Measure ordinary cleanup, then set a stage budget. |
| High responsiveness risk | Synchronous Accessibility calls have no explicit timeout | [Insertion service](../../../../DictationApp/Infrastructure/Accessibility/AccessibilityTextInsertionService.swift#L31) and [editor tree traversal](../../../../DictationApp/Infrastructure/Accessibility/AccessibilityTextInsertionService.swift#L411). Restore the timeout contract, stop on messaging failure, and bound optional tree inspection. |
| High-confidence local cleanup | Recording state drives forced window layout at 10 Hz | [Recording loop](../../../../DictationApp/Engine/DictationCoordinator.swift#L381) and [overlay controller](../../../../DictationApp/Presentation/Overlay/OverlayWindowController.swift#L36). Publish on displayed-second and warning changes. Initial overlay construction also runs before the pipeline starts. Profile first-use presentation separately. |
| Delivery settlement | Readback sleeps 200 ms before its first attempt and can accumulate 400 ms of sleep | [Verification](../../../../DictationApp/Infrastructure/Accessibility/AccessibilityTextInsertionService.swift#L243). These waits occur after dispatch. The caller also discards positive range or caret evidence if it lacks an expected whole value. Fix that mismatch while preserving the pasteboard hold. |
| Candidate for measurement | Clipboard snapshots and editor preparation precede paste | [Clipboard materialization](../../../../DictationApp/Infrastructure/Clipboard/ClipboardSnapshot.swift#L15) reads every available representation. [Insertion](../../../../DictationApp/Infrastructure/Accessibility/AccessibilityTextInsertionService.swift#L123) builds the expected whole document. Time each and defer verification-only work when possible. |
| Candidate for measurement | Startup performs synchronous I/O and per-session setup | [AppModel](../../../../DictationApp/App/AppModel.swift#L310) loads Settings and checks readiness before accepted-start timing. [Recorder](../../../../DictationApp/Infrastructure/Audio/CoreAudioRecorder.swift#L62) refreshes audio devices and creates the recording directory on the main actor before queuing AUHAL setup. Measure before moving I/O or changing device resolution. |
| First-syllable risk | The start cue can precede microphone readiness | [Capture startup](../../../../DictationApp/Engine/DictationCoordinator.swift#L261) enqueues the cue before preparing the recorder. Measure cue onset relative to first accepted audio if users take it as their signal to speak. |

## Phase 1 · Instrument and establish the baseline

**Status** · Instrumentation implemented, sample collection pending

- Capture the shortcut timestamp before scheduling main-actor work.
- Reuse the existing capture instrumentation and distinguish first accepted
  audio from the main-actor recording transition.
- Record finalization, provider, clipboard, and insertion intervals defined
  in the spec. Include attempts and backoff in provider measurements.
- Collect comparable samples with a built-in input and representative
  native and rich-text editors. Use a Bluetooth route for a separate
  startup comparison when available.

Complete this phase after Debug and Release builds succeed and the recorded
data accounts for Stop-to-dispatch and dispatch-to-outcome independently.
Review emitted fields for sensitive content.

## Phase 2 · Reduce local work

**Status** · Implemented, live editor verification pending

- Coalesce elapsed updates while maintaining the existing duration and
  control-event checks.
- Enforce the Accessibility timeout before focus resolution and abort
  probing on a messaging failure. Bound the fallback tree walk and skip it
  if a semantic placeholder match already establishes that the editor is
  empty. Evaluate batched attribute reads if AX round trips are material.
- Honor positive insertion evidence without requiring a whole-document
  value. Measure clipboard materialization before changing snapshot behavior.
- Use the traces to decide whether initial overlay layout, Core Audio
  discovery, recording-directory I/O, or artifact validation merits further
  work. Preserve the dedicated per-session AUHAL and fresh device resolution.

Complete this phase after Debug and Release builds succeed. Compare overlay
update counts and delivery timings against the baseline. Verify first capture,
rapid stop and restart, cancellation, rich-text insertion, and clipboard
ownership manually.

## Phase 3 · Bound cleanup latency

**Status** · Implemented, live provider verification pending

- Start with the content-scaled deadline in the specification. Use separate
  timing and fallback classifications to evaluate it with live measurements.
- Pass the budget through the provider and retry boundaries. Cancel pending
  attempts at the deadline, deliver raw text once, and reject late results.
- Move runtime Keychain reads off the main actor so a slow credential lookup
  cannot block UI work or delay raw fallback. Measure the cloud path before
  sharing an ephemeral URLSession between stages. Use
  URLSession task metrics to check connection reuse and preserve individual
  stage timeouts.

Complete this phase after Debug and Release builds succeed. Compare the
cleanup-enabled path against the baseline and manually verify successful
cleanup, cancellation, and raw fallback on transient failure.

## Follow-up · Overlap transcription with capture

The [live Apple On-Device plan](11-live-apple-transcription.md) covers
overlapping analyzer preparation and recognition with capture, bounded
input, and completed-file recovery. It records verification for that path
separately.

## Parallel release priority · OpenAI model migration

The [OpenAI model migration plan](10-openai-model-migration.md) records the
replacement of the retiring cleanup and transcription models and the
matching changes to production and Settings requests.

## Implementation evidence

- Unsigned macOS arm64 Debug and Release builds passed with Xcode 27.2.
  Swift compilation emitted no application source diagnostics. Xcode
  reported host device-support and simulator framework warnings.
- Source inspection confirmed that elapsed ticks publish only when the
  displayed second or warning changes. Automatic stop still checks raw
  monotonic elapsed time.
- Cleanup expiry cancels the outstanding provider task and makes the raw
  result available independently of task teardown. A cancelled or late
  provider result cannot perform delivery. Keychain reads for dictation and
  cleanup run off the main actor.
- Insertion records separate timing for clipboard preparation, Accessibility
  preparation and verification, outcome, and actual clipboard restoration.
  Stop-to-dispatch timing is correlated with the same in-memory session ID.
- Live Stop-to-paste percentiles, cross-app paste, and cloud requests remain
  pending manual verification.
