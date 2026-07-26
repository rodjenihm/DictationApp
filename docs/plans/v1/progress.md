# DictationApp v1 Implementation Progress

This file is the durable handoff record between implementation sessions.

- Authoritative specification: [`docs/specifications/v1/application.md`](../../specifications/v1/application.md)
- Approved implementation plan: [`docs/plans/v1/initial-implementation.md`](initial-implementation.md)

## Slice status

| Slice | Status | Verification |
| --- | --- | --- |
| 1. Menu-bar utility shell | Complete | Debug and Release builds passed; signed bundle metadata, entitlements, architecture, activation policy, setup-window presence, process persistence, and clean termination verified |
| 2. First-run configuration, preferences, and credentials | Complete | Signed Debug and Release builds, bundled fixture metadata, live OpenAI validation, transactional failure paths, Keychain CRUD, persistence, relaunch, and derived status verified |
| 3. Permission flows and configurable global shortcut | Next | — |
| 4. Local capture, explicit session state, and sound cues | Pending | — |
| 5. Non-activating overlay and cancellation-safe cleanup | Pending | — |
| 6. Provider-neutral completed-file OpenAI transcription | Pending | — |
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

## Session handoff rules

1. Read the specification, implementation plan, and this file before changing code.
2. Confirm the current repository matches the recorded completed-slice state.
3. Do not repeat completed-slice acceptance checks unless later changes touch or regress that behavior.
4. Implement only the slice marked `Next`.
5. Keep the application runnable and stop after that slice for review.
6. After verification, mark the slice `Complete`, record its evidence, and mark the following slice `Next`.
7. Do not modify the specification without explicit approval.

## Next action

Implement **Slice 3 — Permission flows and configurable global shortcut**.
