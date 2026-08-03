# Microphone Selection Implementation Plan

**Status:** Complete

**Specification:** `docs/specifications/v1/features/05-microphone-selection.md`

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Specification and architecture | Complete | Defined persisted preference, live discovery, fallback, capture ownership, active-session, failure, and scope requirements | Approved grilling decisions and feature specification |
| 2. Domain, persistence, and discovery | Complete | Added transactional built-in/System Default/stable-UID preferences and live Core Audio input snapshots | Debug build and source inspection |
| 3. Settings and recording presentation | Complete | Added the saved microphone picker, unavailable state, and active fallback indication | Debug build and source inspection |
| 4. Dedicated selected-device capture | Complete | Added a recorder-owned AUHAL lifecycle and bounded first-buffer startup | Debug build and source inspection |
| 5. Build and hardware verification | Complete | Passed builds and live built-in capture, cancellation, and finalization while AirPods remained the output route | Debug/Release builds, repository checks, and live Core Audio logs |

## Architecture

- `AppConfiguration` owns the transactional persisted microphone preference;
  `SessionConfiguration` snapshots it at session start.
- `CoreAudioInputDeviceService` publishes immutable MainActor snapshots of
  alive, input-capable Core Audio devices through Observation without opening
  them for capture; Settings tracks those snapshots directly for live updates.
- `ConfigurationViewModel` keeps microphone edits in the same Save/Cancel
  transaction as other General settings.
- `CoreAudioRecorder` owns one dedicated AUHAL input unit per prepared capture
  candidate and serializes unit lifecycle and writer operations on its runtime
  queue.
- The recorder binds the resolved device directly to the AUHAL, renders through
  its input callback, and observes that same device for active disconnects.
- `PreparedRecording`, `ActiveSession`, and `RecordingSessionState` carry the
  resolved display name and fallback state to menu and overlay presentation.
- Xcode uses file-system-synchronized groups, so new files under
  `DictationApp/` need no project membership edits.
- The target uses Swift 5 language mode, complete strict concurrency,
  approachable concurrency, and MainActor default isolation.

## Implementation phases

### Phase 1 — Specification and architecture

- Resolve defaults, System Default, unavailable-device fallback,
  active-session pinning, live Settings discovery, presentation, and scope.
- Confirm Core Audio device enumeration and AUHAL selected-device lifecycle.
- Record the canonical feature specification and implementation ledger.

Gate: specification contains no open product decisions.

### Phase 2 — Domain, persistence, and discovery

- Add a Codable/Equatable/Sendable microphone preference supporting built-in,
  System Default, and stable-UID choices with last-known names.
- Add it to `AppConfiguration`, Settings drafts/baselines, and immutable
  `SessionConfiguration` snapshots.
- Enumerate alive input-capable Core Audio devices, identify built-in transport,
  resolve default input, and refresh on device-list/default-input changes.
- Normalize the first-run built-in default to System Default when no built-in
  input exists.

Gate: stable UID identity, live MainActor snapshots, non-activating discovery,
and transactional persistence are source-verified and compile.

### Phase 3 — Settings and presentation

- Add a Recording group below Permissions with System Default, connected
  inputs, and a retained unavailable choice.
- Show unavailable/fallback explanatory text without preview or metering.
- Include the preference in General dirty-state, Save, rollback, and reload.
- Carry fallback state through prepared, active, recording, menu, and overlay
  value types.

Gate: picker identity, unavailable presentation, session pinning, fallback
copy, and accessibility compile and are source-verified.

### Phase 4 — Dedicated selected-device capture

- Replace the engine-owned input tap with one AUHAL input unit per candidate.
- Enable input, disable output, bind the candidate, configure deterministic
  mono PCM, allocate the maximum-slice buffer, install the input callback, and
  initialize in Core Audio's required order.
- Preserve the asynchronous M4A writer as the callback's sole consumer.
- Keep AUHAL control and teardown on the recorder's serial runtime queue.
- Bound first-buffer startup at two seconds.
- Preserve one System Default preparation fallback, active-device observation,
  partial recovery, immediate cancellation, and termination ownership.
- Separate best-effort AUHAL stop/uninitialize diagnostics from M4A writer
  finalization so a safely disposed disconnected device can still produce a
  valid partial artifact.

Gate: one owner controls device binding and I/O-unit lifecycle, callback state
outlives the running unit, teardown cannot overlap disposal, macOS routing is
unchanged, and startup cannot suspend indefinitely.

### Phase 5 — Build and verification

- Build Debug and Release with complete strict concurrency.
- Run `git diff --check` and privacy-sensitive source searches.
- Exercise built-in preference while AirPods remain the default/output route,
  plus normal stop and cancellation.
- Keep System Default, unavailable preference/reconnect, and active-device
  disconnection as explicit manual matrix scenarios.

Gate: builds and repository checks pass; built-in capture reaches recording,
stops successfully, and does not activate the AirPods input route.

## Verification evidence

- 2026-08-02: Debug and Release builds succeeded with complete strict
  concurrency; Release used whole-module optimization.
- 2026-08-02: `git diff --check` and final privacy/source review passed.
- 2026-08-02: Live verification recorded through the built-in microphone while
  AirPods remained the output/default route. Core Audio logs showed no AirPods
  input route and no post-start route replacement.
- 2026-08-02: First buffers arrived in 42–45 ms; recording state was reached
  in 110–186 ms.
- 2026-08-02: Cancellation stopped and disposed the built-in AUHAL cleanly.
- 2026-08-02: Normal local-only stop finalized the M4A in 28 ms and returned to
  idle.
- 2026-08-03: The complete feature was restored after an explicit temporary
  revert; Debug and Release builds were rerun.
- 2026-08-03: Review fixes made device snapshots observable, moved picker
  matching to kind/UID identity, refreshed last-known names on save, and made
  writer finalization authoritative after safe AUHAL disposal.
- 2026-08-03: Review-fix Debug and Release builds succeeded. Final
  `git diff --check`, privacy-log search, stale recorder/picker identity search,
  and changed-path scope review passed.

## Assumptions

- The host exposes one built-in Core Audio input on MacBook hardware.
- System Default is the only automatic fallback; DictationApp does not guess
  among arbitrary remaining devices.
- Device names are presentation metadata and may change; UIDs are identity.
- Build artifacts stay outside the repository.
- No automated test target is added.
