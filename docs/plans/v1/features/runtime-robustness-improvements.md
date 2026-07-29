# Runtime Robustness Improvements Implementation Plan

**Status:** Complete

**Specification:** `docs/specifications/v1/features/runtime-robustness-improvements.md`

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Nonblocking recorder cancellation and Sendable ownership | Complete | Recorder ownership invalidates on MainActor and AVFoundation teardown runs asynchronously on the serialized capture queue; the capture-context Sendable invariant is explicit | 2026-07-29: Complete-strict Debug build succeeded; source check found no `captureQueue.sync` |
| 2. Lossless pipeline control-event delivery | Complete | The per-session stream is unbounded and rejected or terminated partial-capture events delete their owned artifacts | 2026-07-29: Complete-strict Debug build succeeded; source audit covered all `submit`, `yield`, and `finish` paths |
| 3. End-to-end cancellation semantics | Complete | Settings validation preserves cancellation, cancelled URLSession validation is normalized, and paste settlement performs no verification or clipboard mutation after cancellation | 2026-07-29: Complete-strict Debug build succeeded; cancellation catch ordering and insertion suspension paths were source-verified |
| 4. Off-main transcription payload preparation | Complete | Audio validation, file IO, and multipart request construction run in a private concurrent helper; one immutable request is reused across retries | 2026-07-29: Complete-strict Debug build succeeded; source check confirmed cancellation gates around preparation and request dispatch |
| 5. Bounded Accessibility messaging | Complete | AX messaging is globally bounded to one second per request, cancellation is checked between operations, and pre/post-paste failures retain their existing outcome semantics | 2026-07-29: Complete-strict Debug build succeeded with no source diagnostics; AX timeout and cancellation branches were source-verified |
| 6. Settings Observation, strict configuration, and final integration | Complete | Settings uses Observation with tracked publisher revisions and page-scoped views; Complete strict checking is persisted in both configurations | 2026-07-29: clean Debug and Release builds succeeded with persisted Complete checking and no Swift source diagnostics; the signed app launched background-only/non-frontmost, two rapid cancel/restart cycles completed serialized teardown, and active-session Quit completed bounded cleanup |

Update this table after every phase. A phase becomes Complete only after its
gate passes, and only one incomplete phase may be Next.

## Summary

Implement all required and optional hardening from the specification without
changing DictationApp's external behavior or public interfaces. Keep Swift 5
language mode, MainActor default isolation, and Approachable Concurrency while
enabling Complete strict-concurrency diagnostics.

## Phase 1 — Nonblocking recorder cancellation and Sendable ownership

- Invalidate the active recorder context, observers, and continuations
  synchronously on the main actor.
- Enqueue AVFoundation stop and cleanup operations on the existing capture
  queue without waiting from the main actor.
- Serialize replacement-session hardware preparation behind teardown.
- Keep late delegates scoped to stale-artifact deletion.
- Make the capture context explicitly nonisolated, retain the narrow unchecked
  Sendable boundary, document its ownership invariant, and add queue
  preconditions where practical.

Gate: Debug build succeeds with command-line
`SWIFT_STRICT_CONCURRENCY=complete`, and normal cancellation contains no
synchronous capture-queue wait.

## Phase 2 — Lossless pipeline control-event delivery

- Use an unbounded per-session event stream so elapsed updates cannot evict
  control events.
- Inspect yield results and delete partial artifacts rejected by a terminated
  stream.
- Preserve structured timer lifetime, monotonic duration decisions, and
  session-token isolation.

Gate: Complete-strict Debug build succeeds and every stream producer and
termination path has explicit artifact ownership.

## Phase 3 — End-to-end cancellation semantics

- Preserve `CancellationError` through provider Settings modules.
- Normalize cancelled URLSession validation to cancellation.
- Propagate cancellation from paste-consumption waiting.
- Perform no Accessibility verification or clipboard payload replacement after
  insertion cancellation.

Gate: Complete-strict Debug build succeeds; Settings validation cancellation
does not create an issue, and insertion has no post-cancellation side effects.

## Phase 4 — Off-main transcription payload preparation

- Prepare and validate transcription upload data in a private `@concurrent`
  helper using Sendable values.
- Build one immutable request body per operation and reuse it across retries.
- Check cancellation before and after preparation and before each request.
- Preserve credential timing, request limits, error mapping, and retry policy.

Gate: Complete-strict Debug build succeeds and recording IO/multipart
construction is reachable only through the concurrent helper.

## Phase 5 — Bounded Accessibility messaging

- Apply a one-second process-global AX messaging timeout.
- Map pre-paste failures to the existing failed/manual-paste path and
  post-paste verification failures to Unverified.
- Check cancellation between AX operations.
- Narrowly preconcurrency-import ApplicationServices for its immutable
  unannotated trust-prompt constant.

Gate: Complete-strict Debug build succeeds and pre/post-paste outcome mapping
preserves current focus, clipboard, and insertion behavior.

## Phase 6 — Settings Observation, strict configuration, and final integration

- Migrate only `ConfigurationViewModel` to Observation and use `@Bindable` in
  Settings views.
- Bridge provider and runtime-health publishers through tracked revision
  values.
- Extract concrete shell, sidebar/footer, General, Transcription,
  Post-processing, and Providers views with narrow observed inputs.
- Preserve focus routing, validation clearing, navigation, accessibility, and
  transactional save behavior.
- Remove the duplicate transcription-provider selection call.
- Persist Complete strict-concurrency checking in Debug and Release.

Gate: clean Debug and Release builds succeed with no concurrency, Sendable,
deprecation, or availability diagnostics.

## Final verification

- Exercise recording Stop, cancellation, immediate replacement, and active
  quit.
- Exercise Settings validation cancellation and draft preservation.
- Exercise transcription success, retry, cancellation, and retained recovery.
- Exercise confirmed, unverified, manual-paste, and cancelled insertion paths.
- Navigate, edit, discard, save, reopen, and repair across all Settings pages.
- Confirm menu, overlay, focus, accessibility, clipboard, privacy, and
  non-activation invariants.
- Run `git diff --check` and repository artifact/privacy checks.

No automated test target or Instruments trace is added.

### Evidence

- 2026-07-29: Clean unsigned Debug and Release builds completed from Derived
  Data under `/tmp`. Quiet rebuilds emitted no Swift compiler, Sendable,
  deprecation, or availability diagnostics.
- 2026-07-29: A freshly signed Debug build launched as a background-only,
  non-frontmost application with its native application menus available.
- 2026-07-29: Two shortcut-started sessions were cancelled in rapid
  succession. Structured logs showed cancellation teardown scheduled,
  coordinator ownership released, and teardown completed for each session;
  no provider or clipboard operation was entered.
- 2026-07-29: Quitting during active capture logged bounded shutdown start,
  immediate capture-resource release, session cleanup, and shutdown completion;
  the process exited.
- 2026-07-29: Settings validation, provider retry/recovery, insertion outcome,
  Settings navigation/focus, stream ownership, and clipboard transaction paths
  were source-verified. Live provider requests and cross-application clipboard
  or Accessibility delivery were not invoked unattended because they depend on
  user credentials, billable/external services, and a user-owned target
  document.
- 2026-07-29: `git diff --check` passed. Repository artifact and credential-like
  content scans found no generated build output, Instruments traces, result
  bundles, or newly embedded credentials.

## Assumptions

- OpenAI remains the only provider.
- Existing recording, retry, model, prompt, Keychain, clipboard, and UI
  behavior remains unchanged outside the specification.
- Build artifacts stay outside the repository.
- This file is the sole progress ledger for the feature.
- No commits or pushes are created.
