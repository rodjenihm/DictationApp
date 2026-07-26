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
| 6. Provider-neutral completed-file OpenAI transcription | Next | — |
| 7. Recoverable capture failures and configuration repair | Pending | — |
| 8. Independent optional OpenAI post-processing and raw fallback | Pending | — |
| 9. Clipboard preservation and Accessibility insertion | Pending | — |
| 10. Cross-stage cancellation and state-machine hardening | Pending | — |
| 11. Final v1 integration and polish | Pending | — |

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

## Session handoff rules

1. Read the specification, implementation plan, and this file before changing code.
2. Confirm the current repository matches the recorded completed-slice state.
3. Do not repeat completed-slice acceptance checks unless later changes touch or regress that behavior.
4. Implement only the slice marked `Next`.
5. Keep the application runnable and stop after that slice for review.
6. After verification, mark the slice `Complete`, record its evidence, and mark the following slice `Next`.
7. Do not modify the specification without explicit approval.

## Next action

Implement **Slice 6 — Provider-neutral completed-file OpenAI transcription**.
