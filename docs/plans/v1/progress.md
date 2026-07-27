# DictationApp v1 Implementation Progress

This file is the durable handoff record between implementation sessions.

- Authoritative specification: [`docs/specifications/v1/application.md`](../../specifications/v1/application.md)
- Approved implementation plan: [`docs/plans/v1/initial-implementation.md`](initial-implementation.md)

## Slice status

| Slice | Status | Verification |
| --- | --- | --- |
| 1. Menu-bar utility shell | Complete | Debug and Release builds passed; signed bundle metadata, entitlements, architecture, activation policy, setup-window presence, process persistence, and clean termination verified |
| 2. First-run configuration, preferences, and credentials | Complete | Signed Debug and Release builds, bundled fixture metadata, live OpenAI validation, transactional failure paths, Keychain CRUD, persistence, relaunch, and derived status verified |
| 3. Permission flows and configurable global shortcut | Complete | Signed Debug and Release builds, permission isolation/status refresh, System Settings routing, exclusive shortcut activation, conflict rollback, persistence, and reset verified |
| 4. Local capture, explicit session state, and sound cues | Complete | Signed Debug and Release builds, live menu/shortcut capture, finalized AAC metadata, duration controls, cue playback/toggle persistence, short/cancel/quit cleanup, and idle recovery verified |
| 5. Non-activating overlay and cancellation-safe cleanup | Complete | Signed Debug and Release builds, non-activating two-display overlay behavior, menu/overlay/Escape cancellation, Escape conflict rollback/non-propagation, immediate cross-state cleanup, and startup orphan removal verified |
| 6. Provider-neutral completed-file OpenAI transcription | Complete | Signed Debug and Release builds, provider/retry and coordinator harnesses, both live curated models, Automatic/explicit language, clipboard/no-speech behavior, retained Retry/Discard, cancellation, and cleanup verified |
| 7. Recoverable capture failures and configuration repair | Complete | Signed Debug and Release builds, recoverable-partial state/cleanup harness, transactional repair harness, permanent-provider classification harness, and retained-snapshot invariants verified |
| 8. Independent optional OpenAI post-processing and raw fallback | Complete | Signed Debug and Release builds, provider/coordinator/configuration harnesses, both live curated cleanup models, disabled bypass, clipboard output, fallback timing, health-state skipping/clearing, cancellation, and cleanup verified |
| 9. Clipboard preservation and Accessibility insertion | Complete | Signed Debug and Release builds, clipboard/boundary and coordinator harnesses, native and WebKit automatic paste, live Confirmed/Unverified/Failed outcomes, ownership races, cancellation rollback, and fallback/Dismiss behavior verified |
| 10. Cross-stage cancellation and state-machine hardening | Complete | Signed Debug and Release builds plus a temporary coordinator/settings harness verified every cancellable stage, rapid restart isolation, stale completion suppression, clipboard rollback, repair/retry, and Settings locking |
| 11. Final v1 integration and polish | Next | — |

## Completed slice records

### Slice 1 — Menu-bar utility shell

Implemented:

- Converted the existing target to a menu-bar-only SwiftUI lifecycle.
- Added an AppKit-hosted SwiftUI setup window.
- Added status, unavailable Start, Settings, and Quit menu actions.
- Targeted macOS 15.0 and arm64.
- Retained Hardened Runtime and disabled App Sandbox.
- Added `LSUIElement=true` and the microphone usage description.
- Removed the default `WindowGroup` and template content view.

Verified:

- Signed Debug build succeeded.
- Signed Release build succeeded.
- Debug and Release binaries are arm64 with a macOS 15.0 minimum.
- Hardened Runtime is present in both signatures.
- Built entitlements contain no App Sandbox entitlement.
- Runtime activation policy is `.accessory`.
- Runtime smoke test found one setup window.
- The menu-bar process remained alive and accepted normal termination.
- Repository contained no Derived Data or build artifacts.

Manual verification limitation:

- Automated screenshot and click-path verification was unavailable because the host denied screen-capture and assistive-access automation.
- Visually confirm menu-bar appearance and Settings close/reopen behavior only if a later slice changes the lifecycle or presentation code.

### Slice 2 — First-run configuration, preferences, and credentials

Implemented:

- Added provider-neutral configuration, model-selection, language, and post-processing domain types.
- Added `UserDefaults` persistence for non-sensitive configuration and the first-run presentation marker.
- Added generic-password Keychain CRUD for the OpenAI API key.
- Added centralized OpenAI transcription, post-processing, and language catalogs.
- Added completed-file transcription validation through `/v1/audio/transcriptions`.
- Added post-processing validation through `/v1/responses` with `store:false`.
- Bundled a 0.75-second silent M4A validation fixture.
- Replaced the setup placeholder with reusable onboarding and Settings controls.
- Added masked Replace/Delete credential state, curated/custom models, language selection, upload-boundary disclosure, and transactional validation.
- Derived the menu-bar readiness status from current configuration and credential availability.
- Suppressed onboarding after successful completion while keeping Settings available.

Verified:

- Signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Built entitlements contain no App Sandbox entitlement.
- The validation fixture is bundled as mono 16 kHz AAC/M4A with a 0.750-second duration.
- First-run Settings opened with no Microphone or Accessibility permission prompt.
- A valid key successfully validated `gpt-4o-transcribe` and enabled `gpt-5-mini` post-processing through their live OpenAI endpoints.
- The active configuration and first-run marker persisted across a normal quit and relaunch; onboarding stayed closed and menu status was `Ready`.
- The Keychain item exposed only masked saved state in the UI; the credential was absent from defaults, repository content, and command output.
- An invalid replacement key was rejected while the original Keychain item modification timestamp and active configuration remained unchanged.
- An inaccessible custom transcription model was rejected while `gpt-4o-transcribe` remained active.
- Delete removed the Keychain item and changed Settings/menu status to unconfigured/`Setup required`.
- Re-entering the valid key restored the configuration and `Ready` status.
- Repository contained no Derived Data, build directories, result bundles, or credential-like API-key values.

Manual verification:

- The user performed the credential-entry and Settings interactions directly so the API key never entered chat, shell history, or automation output.
- User-provided screenshots confirmed the masked UI, actionable validation errors, deletion state, and menu readiness transitions.

### Slice 3 — Permission flows and configurable global shortcut

Implemented:

- Added live Microphone and Accessibility status derived from macOS APIs without persisted grant flags.
- Added the Hardened Runtime audio-input entitlement required for macOS to register and authorize the app's microphone request.
- Added explicit permission Enable actions, denied-state explanations, and permission-specific System Settings routing with a root fallback.
- Rechecked permissions whenever Settings opens and whenever the app becomes active.
- Kept Accessibility optional with an explicit clipboard-only explanation.
- Added a separately persisted, codable global shortcut with Option–Space as the backward-compatible default.
- Added a focusable AppKit shortcut recorder requiring a standard modifier, with Escape cancellation and reset to Option–Space.
- Added enabled system-reserved shortcut detection through `CopySymbolicHotKeys`.
- Added exclusive HIToolbox hotkey registration with candidate-first replacement so failures retain the active shortcut.
- Restored shortcut registration at launch and removed the event handler and registration during termination.
- Routed shortcut activation through the app model; configured activation reports that the recording engine is not available in this intermediate slice.
- Added actionable startup and replacement registration errors to Settings.

Verified:

- Signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- Opening and reopening Settings created only the Settings window and triggered no permission prompt.
- After a bundle-scoped TCC reset, Microphone showed `Not requested`; its explicit Enable action advanced to `Allowed`.
- System Settings listed DictationApp under Microphone with its toggle enabled, and the app refreshed to the live allowed status.
- The Microphone and Accessibility flows remained independent and exposed their live statuses.
- Accessibility Enable produced the macOS Accessibility Access flow, while Open System Settings opened the corresponding settings route.
- Option–Space registered exclusively and fired while Finder was active, changing the menu status to `Recording engine not available yet`.
- A temporary Control–Option–Shift–D shortcut registered exclusively, fired from Finder, persisted across relaunch, and was reset to Option–Space.
- Escape exited shortcut recording without changing the active shortcut.
- Enabled Command–Space was rejected as macOS-reserved while the previous shortcut remained registered.
- A separately held exclusive shortcut was rejected as conflicting while the previous shortcut remained registered.
- The saved OpenAI configuration and masked Keychain credential state remained intact; no OpenAI request was made.
- Repository checks found no Derived Data, build directories, result bundles, or credential-like API-key values.

Verification cleanup:

- Left Microphone allowed, matching the user's request to grant the app access.
- Restored and persisted Option–Space as the active shortcut.

Manual verification limitation:

- Screen capture remained unavailable on the host, so window, control, prompt, and menu state were verified through the macOS Accessibility hierarchy instead of screenshots.

### Slice 4 — Local capture, explicit session state, and sound cues

Implemented:

- Added immutable session configuration, recording profile, audio artifact, recording metadata, capture error, and explicit session-state domain types.
- Added a main-actor dictation coordinator owning preparing, recording, finalizing, completion, short-recording, cancellation, failure, and idle transitions.
- Added just-in-time Microphone authorization, per-session default-input resolution, monotonic elapsed-time updates, a 9:30 warning, and a 10:00 automatic stop.
- Added `AVCaptureSession`/`AVCaptureAudioFileOutput` local capture on a dedicated serial queue with M4A/AAC, mono, 16 kHz, and a constant 64 kbps encoder target.
- Added delegate-awaited finalization, `AVURLAsset` duration/audio-track validation, and app-cache artifact creation/deletion.
- Added four distinct macOS system sound cues with completion-aware playback so the start cue finishes before file capture and all other cues follow capture shutdown.
- Added a persisted all-cues toggle that defaults to enabled.
- Replaced the intermediate disabled menu action with shared menu/shortcut Start and Stop behavior, active-session Cancel, elapsed time, input-device name, warning, finalization, completion, and failure statuses.
- Added best-effort synchronous recording shutdown and deletion during application termination.

Verified:

- Final signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- Option–Space and menu actions started/stopped the same real recording flow while another application was active.
- The recording menu showed monotonic elapsed time and the current default input, `Danijel’s AirPods Pro 3`; subsequent sessions resolved the input again.
- Rapid shortcut presses during preparing and finalizing were ignored while the active recording completed normally.
- A finalized capture inspected with `afinfo` was M4A/AAC, mono, 16 kHz, with a configured constant 64 kbps target; quiet AirPods captures reported an approximately 48 kbps encoded payload.
- Valid captures were available during the 1.2-second acknowledgement and then deleted; sub-500 ms, cancelled, failed-quit-check, and active-quit captures left no app-cache recording.
- Temporarily shortened one-second/three-second thresholds exposed the non-blocking warning and automatic stop; production values were restored to 9:30/10:00 before the final builds.
- The mapped macOS system sounds (`Tink`, `Pop`, `Funk`, and `Basso`) resolved and played through the current macOS output route. The Settings toggle persisted disabled and enabled states and was restored to enabled.
- The existing configuration, first-run marker, Keychain credential, Option–Space shortcut, and permission grants remained intact.
- The recording path contains no provider call, and no OpenAI request was made.
- Repository checks found no Derived Data, build directories, result bundles, or credential-like API-key values.

### Slice 5 — Non-activating overlay and cancellation-safe cleanup

Implemented:

- Added a borderless, floating, non-activating `NSPanel` hosting a compact SwiftUI recording pill.
- Anchored each session to the display containing the pointer when preparation begins and retained that display while the pointer or focused application changes.
- Added preparing, recording, duration-warning, finalizing, completed, too-short, cancelled, and capture-failure overlay presentations with pointer-operable Stop and Cancel controls.
- Added an exclusive modifierless Escape hotkey registered before preparation and removed only after the coordinator returns to idle.
- Added actionable Escape registration errors without disturbing the configured global shortcut.
- Expanded cancellation to every non-idle state with synchronous recorder shutdown, task cancellation, artifact deletion, stale-session guards, immediate idle publication, and serialized post-shutdown sound cues.
- Added best-effort startup removal of files scoped to the app-owned recording cache.

Verified:

- Final signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- Starting from TextEdit left TextEdit frontmost and its caret target unchanged while the overlay appeared; overlay Stop and Cancel remained pointer-operable without activating DictationApp.
- A session started with the pointer on the secondary display placed the 500-point overlay at that display's bottom center; moving the pointer to the primary display did not relocate it. A subsequent session started on the primary display appeared there.
- The overlay exposed the active input, elapsed time, finalization status, and existing transient completion/error acknowledgements through the macOS Accessibility hierarchy.
- The configured shortcut and actual menu-bar Start/Cancel actions used the same recording flow as the overlay controls.
- Escape cancelled immediately and did not close TextEdit's open Find bar; after idle, Escape reached TextEdit normally and closed the Find bar.
- A separate process successfully reserved Escape exclusively; DictationApp then refused to start capture or show the overlay. Releasing the conflict allowed the still-registered Option–Space shortcut to start immediately without relaunch.
- Preparing, recording, finalizing, and completed-acknowledgement cancellation returned directly to idle. Finalizing cancellation removed the overlay, and completed-state cancellation reduced the owned recording count from one to zero.
- Cancelling and immediately starting a new session succeeded while serialized cues prevented a late stop/cancel cue from entering the new recording.
- A seeded orphan inside `Recordings` was removed on launch while a sibling cache control file remained untouched; the control file was removed after verification.
- Successful stop, every cancellation path, normal termination, and startup cleanup left no file in the app recording cache.
- The recording/overlay path contains no provider invocation, and no OpenAI request was made.
- Repository checks found no Derived Data, build directories, result bundles, temporary probe files, or credential-like API-key values.

### Slice 6 — Provider-neutral completed-file OpenAI transcription

Implemented:

- Added a provider-neutral transcription request/protocol and failure classification for cancellation, transient, configuration, and non-retryable operation failures.
- Added a reusable three-attempt retry executor with cancellation-aware sleeps, seconds and HTTP-date `Retry-After` support, full-jitter exponential fallback, an eight-second fallback-delay cap, and a thirty-second cumulative-wait cap.
- Added an OpenAI completed-file transcription adapter with per-operation Keychain credential resolution, centralized curated/custom model and language mapping, readable-M4A and sub-25-MiB validation, in-memory multipart requests, a 120-second timeout, JSON text decoding, provider-private error parsing, and `URLSessionTask` cancellation.
- Enabled OpenAI automatic chunking so completed recordings are loudness-normalized and passed through server voice activity detection before transcription, preventing near-silent captures from being forced into hallucinated text.
- Expanded the coordinator with uploading/transcribing, clipboard success, no-speech, and retained transcription-failure states while preserving the immutable session snapshot and session-generation guards.
- Deleted audio immediately after successful transcription, trimmed only surrounding whitespace, copied non-empty raw text to the clipboard, and left the clipboard unchanged for empty or whitespace-only output.
- Retained one failed artifact and blocked new recordings until explicit Retry, Discard, Cancel/Escape, or quit; each explicit Retry starts a fresh logical provider operation and resolves the credential again.
- Added non-activating overlay and menu progress plus Retry/Discard actions, with Discard equivalent to cancellation and terminal success/no-speech acknowledgements releasing Escape.
- Kept post-processing and Accessibility insertion out of this slice.

Verified:

- Final signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- A temporary provider harness verified Automatic-language omission, explicit Serbian mapping, both curated API model identifiers, three-attempt 5xx and timeout handling, seconds and HTTP-date `Retry-After`, one/two-second exponential bounds, the thirty-second cumulative wait cap, quota non-retry, malformed-response non-retry, cancellation, and pre-request upload-size rejection.
- A temporary coordinator harness verified that no provider request occurs before Stop; exhausted failure retains audio and blocks Start; explicit Retry reuses the artifact and deletes it on success; whitespace output leaves the clipboard untouched; cancellation prevents stale state/clipboard writes; and Discard removes retained audio.
- Live signed-app recordings successfully transcribed with `gpt-4o-transcribe` plus Automatic language and `gpt-4o-mini-transcribe` plus an explicit Serbian hint. Each replaced a clipboard marker with provider output, returned to idle, and left no recording file.
- Follow-up silence handling was corrected after live near-silent recordings produced spurious multilingual text; the multipart request now explicitly selects OpenAI automatic VAD chunking. A three-second live silent capture then preserved a known clipboard marker, returned through the no-speech success path, and left no recording artifact.
- The original `gpt-4o-transcribe`/Automatic configuration, enabled post-processing preference, Keychain credential, shortcut, permissions, and sound-cue preference were restored after verification.
- The active pipeline contains no post-processing or Accessibility insertion call and no logging of credentials, authorization headers, request bodies, provider bodies, audio, or transcripts.
- Temporary harness sources and executables were removed; repository checks found no Derived Data, build directories, result bundles, credential-like API-key values, or other verification artifacts.

### Slice 7 — Recoverable capture failures and configuration repair

Implemented:

- Added active-input disconnection and capture-session runtime-error observation, while retaining the recording delegate as a second unexpected-termination signal.
- Serialized unexpected finalization, removed observers on every teardown path, and emitted at most one validated partial outcome.
- Validated partial M4A duration, audio-track presence, readability, and nonzero file size before transferring artifact ownership to the coordinator.
- Added a single retained failed-session context containing the original immutable session snapshot, artifact, cue preference, and an optional validated transcription repair.
- Added a recoverable capture-failure state with explicit Transcribe Partial and Discard actions in the menu and non-activating overlay; partial audio is never uploaded automatically.
- Deleted short, invalid, stale, duplicate, discarded, cancelled, and quit-time partial artifacts while continuing to block new recording until a valid retained partial or transcription failure is resolved.
- Expanded provider-neutral permanent transcription failure handling and OpenAI invalid-credential/unavailable-or-incompatible-model classification.
- Added a restricted repair Settings presentation containing only credential replacement and transcription provider/model controls.
- Made repair validation transactional: failed validation preserves the saved credential and configuration, while successful validation records a provider/model override for the retained session.
- Kept the retained session's original language, recording profile, and post-processing snapshot immutable; Retry resolves the credential freshly and applies only the validated transcription provider/model repair.

Verified:

- Final signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- A temporary coordinator harness verified valid-partial retention, no automatic provider call, blocked new recording, explicit partial transcription, duplicate/stale callback cleanup, short/invalid partial errors, Discard, successful deletion, and quit cleanup.
- The coordinator harness also verified that repaired Retry reused the retained artifact, changed only the transcription model, preserved the original explicit language and non-transcription session fields, and deleted the artifact after success.
- A temporary configuration harness verified always-on repair validation, transactional invalid-key failure, successful credential/model replacement, callback delivery, and preservation of language, post-processing, sound-cue, and first-run settings.
- A temporary provider harness verified that invalid credentials and unavailable/incompatible models are non-retryable configuration failures, while quota exhaustion remains non-retryable but outside the repair classification.
- Temporary harness sources, executables, module caches, signed build products, and logs were removed; repository checks found no Derived Data, build directories, result bundles, credential-like API-key values, or verification artifacts.

Manual verification limitation:

- A physical active-input disconnect was not performed on the user's current audio hardware. The notification/delegate recovery paths compile and their outcome handling is harness-verified; repeat the real hardware disconnect check during final Slice 11 integration.

### Slice 8 — Independent optional OpenAI post-processing and raw fallback

Implemented:

- Added provider-neutral post-processing configuration, request, and provider contracts.
- Added a centralized output policy that trims only external whitespace, preserves internal paragraphs, bounds visible output length, derives a 64–4096 Responses token budget, and rejects empty or structurally implausible cleanup output.
- Added an OpenAI Responses adapter with per-operation Keychain resolution, immutable cleanup instructions, JSON-serialized untrusted transcript input, explicit empty tools, `store:false`, a sixty-second timeout, curated/custom model mapping, ordered completed-response `output_text` extraction, and the shared three-attempt retry/failure policy.
- Extended the immutable-session coordinator pipeline to delete audio after successful transcription, bypass cleanup when disabled, publish cancellable cleanup progress when enabled, copy validated cleanup output, and use a 2.5-second cue-free raw-transcript fallback for every cleanup failure.
- Preserved session-generation checks across provider completion, output validation, clipboard writes, cancellation, and fallback acknowledgements.
- Added non-persisted provider/model health tracking so known configuration failures skip matching future requests, while successful enabled-cleanup credential/model validation clears attention and unrelated Settings saves do not.
- Added cleanup progress, raw fallback, and Needs Attention presentation to the overlay, menu status, and Settings without repair dialogs, retry actions, prompts, presets, or insertion behavior.

Verified:

- Final signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- A temporary loopback provider harness verified the direct `/v1/responses` request shape, authorization presence, immutable instructions, JSON data input, `store:false`, empty tools, curated model mapping, character/token bounds, ordered completed-response output extraction, three-attempt transient retry, configuration non-retry, and structural output rejection.
- A temporary coordinator harness verified disabled bypass, cleaned clipboard success, invalid-output and provider raw fallback, the 2.5-second fallback state, no fallback failure cue, audio deletion before cleanup, known-bad configuration skipping, validation-based health clearing, and cancellation guards against late clipboard writes.
- A temporary configuration harness verified enabled-cleanup validation on credential, enablement, and curated-model changes; successful clearing of Needs Attention; and no validation or clearing for unrelated Settings changes.
- Live OpenAI adapter checks validated both `gpt-5-mini` and `gpt-5-nano` independently using the existing Keychain credential without printing the key or transcripts. The Responses token budget was adjusted to reserve reasoning tokens while retaining the output policy's hard character limit.
- The final signed app completed real recordings with cleanup disabled and with each curated cleanup model while retaining `gpt-4o-transcribe`; every case replaced a clipboard marker, returned to Ready, and left no recording artifact.
- The original enabled/`gpt-5-mini` configuration and pre-verification clipboard content were restored.
- Temporary harness sources, executables, module caches, signed build products, and logs were removed; repository checks found no Derived Data, result bundles, credential-like API-key values, transcripts, or unrelated changes.

### Slice 9 — Clipboard preservation and Accessibility insertion

Implemented:

- Replaced the one-way transcript pasteboard writer with an in-memory clipboard snapshot and ownership-tracked transaction.
- Materialized every available pasteboard item and data type before replacement, preserved item order, and restored the snapshot only while the transaction's `changeCount` still matched.
- Added provider-neutral Confirmed, Unverified, and Failed insertion outcomes plus a focused-target Accessibility/CoreGraphics insertion service.
- Resolved the focused element only after final text was available, required a writable selected-text attribute, and posted exactly one PID-targeted Command–V without a preceding AX write or retry insertion.
- Added UTF-16 selection replacement and Unicode boundary spacing for letters, marks, decimal digits, and connector punctuation, temporarily applying the prepared payload to the owned clipboard while leaving the retained fallback transcript unchanged.
- Held clipboard restoration through a bounded paste-consumption window so native and web targets read the transcript before confirmed/cancelled restoration can occur.
- Added explicit inserting, confirmed-success, unverified, and clipboard-fallback states across the coordinator, menu, and non-activating overlay.
- Restored still-owned clipboard contents after confirmed insertion or cancellation, abandoned snapshots after unverified/failed completion, and preserved newer external clipboard contents in every race.
- Kept raw cleanup fallback delivery independent, showing inserted success for confirmed delivery and clipboard-ready messaging when automatic insertion was unavailable.
- Added six-second unverified/clipboard fallback acknowledgements with Dismiss while retaining the existing 1.2-second success and 2.5-second raw-fallback timings.

Verified:

- Final signed Debug and Release builds succeeded for arm64 with a macOS 15.0 minimum and Hardened Runtime.
- Final Debug and Release signatures contain `com.apple.security.device.audio-input`; neither contains the App Sandbox entitlement.
- A temporary clipboard and boundary harness verified mixed binary/string item materialization, item order, empty clipboard restoration, delayed paste-window restoration, ownership change-count races, cancellation rollback, UTF-16 replacement, beginning/empty targets, selection replacement, and whitespace, punctuation, newline, Unicode-letter/mark, and connector-punctuation boundaries.
- A temporary coordinator harness verified cleanup-disabled raw delivery, cleanup-enabled cleaned delivery, raw cleanup fallback, Confirmed restoration, Unverified/Failed snapshot abandonment, six-second fallback states, Dismiss, one insertion attempt, and cancellation rollback before insertion.
- A development-signed live probe sharing the app's trusted code requirement automatically pasted into disposable AppKit and WebKit targets. Native and WebKit textarea caret insertion produced `hello brave world`, and WebKit textarea selection replacement produced `hello kind world`, all with Confirmed readback.
- A chat-style WebKit `contenteditable` target automatically inserted `hello brave world` once and produced Unverified because WebKit normalized its boundary spaces to non-breaking spaces; the raw transcript remained available through the clipboard path.
- A focused non-text button and an unsigned/untrusted probe produced Failed without posting a second insertion, covering unavailable targets and denied Accessibility.
- Focused targets were resolved at the AX call rather than retained from recording start; no application, caret, selected range, transcript, or clipboard snapshot was persisted or logged.
- Existing provider configuration, Keychain credential, shortcut, permissions, and sound-cue preference were not modified, and no OpenAI request was made during Slice 9 verification.

### Slice 10 — Cross-stage cancellation and state-machine hardening

Implemented:

- Replaced the separate start/finalization task ownership with one token-scoped session pipeline and an internal event stream spanning preparation, recording, recovery, provider work, insertion, and terminal delivery.
- Added a centralized token-checking transition reducer and validated session ownership after every asynchronous boundary before state, artifact, provider-result, clipboard, or insertion side effects.
- Structured elapsed-time updates under the pipeline and routed Stop, automatic-limit, unexpected-capture, partial-transcription, repair, and Retry actions through the current session stream.
- Made cancellation invalidate session ownership first, cancel the pipeline and network work, stop only the matching recorder session, delete owned audio, clear retained text/session data, conditionally restore the clipboard, and publish idle synchronously.
- Tagged recorder preparation and delegate callbacks with the session identifier, rejected late preparation, and ignored stale start/finish callbacks without disturbing a newer recorder context.
- Added an explicit clipboard cancellation hook with reliable deferred restoration after a posted paste while preserving newer external clipboard contents.
- Added live editable/read-only/transcription-repair Settings access modes, disabled local controls with an explanation during active work, guarded mutation methods, and blocked dictation start during configuration validation.

Verified:

- Final signed Debug and Release builds succeeded for arm64.
- Both final application bundles passed strict deep code-signature verification.
- A temporary coordinator harness verified cancellation during preparation, finalization, transcription, post-processing, insertion, and retained transcription failure.
- The harness verified immediate restart after cancellation, deletion of late finalized artifacts, suppression of delayed provider output and stale recorder callbacks, and no late state, clipboard, or insertion writes into the new session.
- The harness verified cancellation-time clipboard rollback, preservation when ownership was lost, successful configuration repair plus Retry through the same session event stream, restricted repair access, read-only Settings mutation guards, and idle re-enablement.
- Cancellation-insensitive fake provider and insertion operations were deliberately resumed after cancellation; session-token checks kept the coordinator idle or in the newer recording and prevented late delivery.
- Temporary harness sources, executables, module caches, and signed build products were removed; repository checks found no Derived Data, build directories, result bundles, credential-like values, or verification artifacts.

## Session handoff rules

1. Read the specification, implementation plan, and this file before changing code.
2. Confirm the current repository matches the recorded completed-slice state.
3. Do not repeat completed-slice acceptance checks unless later changes touch or regress that behavior.
4. Implement only the slice marked `Next`.
5. Keep the application runnable and stop after that slice for review.
6. After verification, mark the slice `Complete`, record its evidence, and mark the following slice `Next`.
7. Do not modify the specification without explicit approval.

## Next action

Implement **Slice 11 — Final v1 integration and polish**.
