# Runtime Robustness Improvements

**Status:** Complete

## Summary

Harden DictationApp's cancellation, event delivery, main-actor responsiveness,
Accessibility insertion, and concurrency boundaries without changing the
application's user-facing workflow.

This specification refines the lifecycle and cancellation requirements in
`docs/specifications/v1/application.md`. It also preserves the transactional
Settings behavior defined by
`docs/specifications/v1/features/01-tabbed-settings.md`.

The work is intentionally incremental. Each section can be implemented and
reviewed independently, and no section requires a broad rewrite of the
dictation pipeline, provider abstraction, Settings architecture, or AppKit
integration.

## Goals

- Make cancellation return the application to idle without synchronously
  waiting for AVFoundation teardown.
- Guarantee delivery of session-control events while allowing high-frequency
  presentation updates to be coalesced.
- Preserve cancellation as cancellation across Settings validation, provider
  operations, retry delays, insertion, and recovery.
- Keep synchronous file IO, large payload construction, and potentially slow
  cross-process work from blocking the main actor.
- Bound Accessibility communication with an unresponsive target application.
- Keep stale callbacks and cancelled work from mutating newer sessions,
  clipboard state, or presentation state.
- Clarify unsafe Sendable boundaries and executor ownership where framework
  objects cross isolation domains.

## Non-goals

- Change recording formats, duration limits, sound cues, provider models,
  prompts, retry counts, or retry timing.
- Change the menu-bar, overlay, or Settings information architecture.
- Replace the non-activating AppKit panel or the transactional Settings window.
- Add providers, credentials, accounts, profiles, or configuration options.
- Redesign the coordinator state machine or introduce a new application
  architecture.
- Migrate all `ObservableObject` types to Observation solely for modernization.
- Add an automated test target.
- Record an Instruments trace as part of the initial implementation.

## Priority and implementation independence

The improvement areas are ordered by expected value:

1. Nonblocking recording cancellation.
2. Lossless pipeline control-event delivery.
3. End-to-end cancellation semantics.
4. Off-main transcription payload preparation.
5. Bounded Accessibility messaging.
6. Optional concurrency and SwiftUI invalidation hardening.

Each numbered area must remain independently implementable. Completion of one
area must not be required to preserve the current behavior of another.

## 1. Nonblocking recording cancellation

Cancelling an active recording must invalidate application-level ownership
immediately and must not synchronously wait for AVFoundation.

Required behavior:

- Invalidate the current session token before initiating recorder cleanup.
- Cancel the coordinator pipeline and resume any pending recorder continuations
  with cancellation.
- Publish idle state without synchronously dispatching to, or waiting on, the
  audio capture queue.
- Serialize `stopRecording`, `stopRunning`, observer removal, and final artifact
  deletion on the recorder's existing capture boundary.
- Permit a new session to be accepted immediately after cancellation while
  ensuring new hardware preparation does not overlap the previous session's
  serialized teardown.
- Ignore stale AVFoundation delegate callbacks from the cancelled session.
- Delete any late or partially finalized artifact owned by the cancelled
  session.
- Preserve the separate bounded termination path; application quit must never
  wait indefinitely for capture teardown.
- Do not play a late cancellation cue after a replacement session has started.

Cancelling during preparation, finalization, or a retained failure must retain
the current behavior when no active capture context exists.

## 2. Lossless pipeline control-event delivery

Session-control events must not compete with coalescible elapsed-time updates in
a lossy buffer.

Control events include:

- User-requested Stop.
- Automatic duration-limit Stop.
- Unexpected capture completion or failure.
- Retry Transcription.
- Transcribe Partial.
- Applied transcription repair.

Required behavior:

- A submitted control event for the current session must either be consumed or
  explicitly rejected because session ownership changed.
- Elapsed-time updates may be coalesced or replaced by newer elapsed values.
- Elapsed-time traffic must never evict a control event.
- If any bounded channel can reject or drop an event containing an owned audio
  artifact, the artifact must be deleted immediately.
- Duration decisions must continue to use a monotonic clock rather than an
  accumulated event count.
- Session replacement must close or invalidate the previous event producer so
  it cannot deliver into the new session.

An unbounded per-session stream is acceptable because recording duration is
bounded, provided the stream and timer terminate when the session ends.

## 3. End-to-end cancellation semantics

Cancellation must remain distinguishable from validation, transport,
configuration, and provider failures.

### Settings validation

- Cancelling Settings validation must produce the existing cancelled save
  result, not a provider issue.
- `CancellationError` must pass through provider Settings modules unchanged.
- Transport-layer cancellation representations, including a cancelled
  `URLSession` request, must be normalized to cancellation at the validation
  boundary.
- Cancellation must not route focus to a configuration issue or display a
  credential, model, or provider-setup error.
- The Settings draft and previously active configuration must remain unchanged.
- Any partially committed Settings work must continue to use the existing
  compensating rollback behavior.

### Provider and retry work

- Cancellation must stop retry scheduling and cancellation-aware retry delays.
- No new provider request may begin after cancellation is observed.
- A response from cancellation-insensitive or already accepted provider work
  must not update state, clipboard contents, retained text, or a replacement
  session.

### Text insertion and clipboard settlement

- Insertion must check cancellation before posting the paste command and after
  every suspension point.
- Once cancellation is observed after paste dispatch, insertion must not
  perform additional Accessibility verification or clipboard payload
  replacement.
- Clipboard restoration must remain owned by the existing clipboard
  transaction.
- Deferred restoration must preserve a newer external clipboard write.
- Cancellation after insertion has already completed must not attempt to undo
  inserted text.

### Recovery

- Retained transcription and partial-capture recovery actions must remain
  scoped to their original session.
- Cancellation must invalidate pending repair, retry, and recovery callbacks.
- A stale recovery completion must not affect a newer recording.

## 4. Main-actor responsiveness

Large transcription payload preparation must not run on the main actor.

Required behavior:

- Reading a completed recording from disk must execute outside main-actor
  isolation.
- Multipart body construction and copying of audio data must execute outside
  main-actor isolation.
- Values crossing that boundary must have explicit Sendable semantics.
- Check cancellation before payload preparation, after preparation, and before
  starting a provider request.
- A cancelled operation may finish unavoidable synchronous local work, but it
  must not start a network request afterward.
- Build the immutable transcription request body once per operation and reuse
  it across transient network retries.
- Preserve the current upload-size validation, M4A validation, credential
  resolution timing, request timeout, error mapping, and retry policy.
- Do not move SwiftUI, AppKit, pasteboard, coordinator state, or application
  presentation work off the main actor.

Post-processing payloads may retain their current implementation unless they
perform comparably large synchronous work.

## 5. Bounded Accessibility messaging

Automatic insertion must not allow an unresponsive target application to block
DictationApp's main actor for an unbounded or system-default interval.

Required behavior:

- Apply an explicit, bounded Accessibility messaging timeout before resolving
  the focused element or reading target attributes.
- Treat timeout and cannot-complete results as unavailable or unverified
  insertion according to whether paste dispatch may already have occurred.
- Before paste dispatch, failure must follow the existing manual-paste fallback
  and leave the final transcript on the clipboard.
- After paste dispatch, inability to verify must follow the existing Unverified
  outcome and must not claim confirmed insertion.
- Preserve the currently focused target and never activate DictationApp during
  insertion.
- Preserve UTF-16 range handling, boundary spacing, clipboard ownership, and
  external clipboard race behavior.
- Cancellation must remain actionable between Accessibility operations.

Moving Accessibility objects across executors is not required. If the
implementation does so, it must document framework thread-safety and Sendable
assumptions rather than relying on unchecked transfer without an invariant.

## 6. Optional hardening

These items are explicitly lower priority and are not required for the first
five areas to be complete.

### Unsafe Sendable boundary

- Document which executor or serial queue owns every mutable field in the
  recorder capture context.
- Keep framework callbacks from directly mutating main-actor-owned state.
- Minimize the scope of `@unchecked Sendable`.
- Add executor or queue preconditions where they make violations observable
  during development.

No change is required if the existing wrapper remains the smallest practical
boundary and its invariant is made explicit.

### Strict-concurrency diagnostics

The current target uses Swift 5 language mode, MainActor default isolation, and
Approachable Concurrency, while the explicit strict-concurrency build setting
is unset.

Enabling stricter diagnostics may be evaluated as a separate change. It must
not be combined with unrelated architecture migration, and any newly exposed
warning must be resolved from the actual isolation boundary rather than with a
blanket `@unchecked Sendable` or `nonisolated`.

### SwiftUI invalidation boundaries

- Preserve current state ownership and bindings.
- Split large Settings sections into independent `View` types only when this
  narrows observed inputs or materially improves maintainability.
- Do not extract computed `@ViewBuilder` properties under the assumption that
  they create independent invalidation boundaries.
- Do not migrate to Observation unless the migration provides a concrete
  invalidation or ownership benefit.

## Accessibility and presentation invariants

- Menu-bar commands must remain fully available throughout each applicable
  session state.
- The overlay must remain non-activating and must not become key or main.
- Existing button labels, roles, accessibility labels, help text, and status
  announcements must be preserved or improved.
- Status and failure information must not rely on color alone.
- Settings validation cancellation must remain operable from its close sheet.
- No improvement may move the insertion target by activating DictationApp.

## Data and privacy invariants

- Do not log transcripts, audio contents, clipboard contents, credentials,
  request or response bodies, custom identifiers, filenames, device names, or
  target application names.
- Keep credentials in Keychain and resolve them at the established provider
  boundary.
- Delete temporary audio according to the existing session ownership rules.
- Do not persist new session, transcript, clipboard, or Accessibility data.

## Acceptance criteria

The feature is complete when all required areas selected for implementation
satisfy their section requirements and:

- Debug and Release builds succeed using Derived Data outside the repository.
- The compiler reports no new concurrency, isolation, Sendable, deprecation, or
  availability diagnostics.
- Active recording cancellation publishes idle without a synchronous wait on
  the capture queue.
- A replacement session cannot receive state, artifacts, callbacks, clipboard
  writes, or insertion results from its predecessor.
- Elapsed-time pressure cannot discard Stop, unexpected-capture, retry,
  partial-transcription, or repair events.
- Cancelling Settings validation returns cancellation without creating a
  provider issue.
- Cancelling during insertion settlement prevents additional verification and
  clipboard payload mutation while preserving owned restoration.
- Transcription audio reading and multipart construction do not execute on the
  main actor.
- Transient transcription retries reuse one prepared request payload.
- An unresponsive Accessibility target produces a bounded fallback or
  unverified outcome without activating DictationApp.
- Existing menu-bar, overlay, Settings, retry, recovery, Keychain, clipboard,
  and insertion behavior remains unchanged outside the requirements above.
- Repository status contains no generated build products, result bundles,
  recordings, transcripts, credentials, or unrelated changes.

## Assumptions

- macOS 15+, SwiftUI with targeted AppKit integration, and the existing Xcode
  target settings remain the baseline.
- OpenAI remains the only implemented provider.
- AVFoundation teardown remains serialized on the existing recorder capture
  queue.
- The application keeps one active dictation session and one Settings window.
- The application specification remains authoritative where this feature does
  not explicitly refine behavior.
