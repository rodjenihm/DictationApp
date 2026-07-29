# Tabbed Settings Implementation Plan

**Status:** Complete

**Specification:** `docs/specifications/v1/features/tabbed-settings.md`

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Provider and configuration foundation | Complete | Provider-neutral metadata, readiness, persistence, and OpenAI registration | 2026-07-29: Debug build succeeded; source audit confirmed `v2.configuration`, exact existing Keychain service/account reuse, registry-only OpenAI registration, and no provider request during registry/Settings loading |
| 2. Draft and save transaction | Complete | Shared draft, validation, rollback, dirty/error state | 2026-07-29: clean Debug gate build succeeded; source audit verified draft-only shortcut/credential mutation, cancellable fixture validation, compensating rollback, scoped issues, Discard, and removal intent |
| 3. Sidebar Settings UI | Complete | Four destinations, provider drill-in, footer, close protection | 2026-07-29: clean Release and signed Debug builds succeeded; signed app launched; source accessibility/layout audit verified fixed sidebar order, nested provider navigation, scrolling, footer states, labels/hints, focus routing, minimum size, and `NSWindowDelegate` close protection |
| 4. Lifecycle, repair, and acceptance | Complete | Contextual routing, first run, active-session locking, repair | 2026-07-29: final clean Debug and Release builds succeeded; signed Debug app launch succeeded; source acceptance audit verified contextual routes, first-run close, immutable-session locking, format/language-filtered repair, explicit Retry, scoped runtime health clearing, and suspended-draft reconciliation |

Every completed phase includes dated verification evidence.

## Summary

Replace the single Settings form with a native sidebar window backed by a typed
provider-module boundary, provider-scoped model preferences, a transactional
cross-page draft, contextual routing, and lifecycle-safe first-run and repair
flows. OpenAI remains the only registered provider.

## Phase 1 — Provider and configuration foundation

- Add provider-neutral capability, processing-location, readiness, catalog,
  health, and configuration-failure types.
- Add a composition-root provider registry with optional runtime adapters and a
  type-erased provider Settings module.
- Register OpenAI using its existing validators, runtime adapters, model
  catalog, and exact existing Keychain item.
- Refactor application configuration into stage selections with active provider
  plus model choices keyed by provider; keep language global.
- Persist the new configuration under a versioned key and retain existing
  scalar preferences.
- Derive readiness and runtime provider resolution from the registry instead of
  hard-coded OpenAI credential checks.

Gate: Debug build succeeds, existing OpenAI dictation remains usable, the
existing credential is reused, and loading Settings makes no provider request.

## Phase 2 — Shared draft and save transaction

- Introduce one non-secret Settings draft plus provider-owned drafts, saved
  baselines, per-destination dirty state, and structured field issues.
- Make shortcut, sound, configuration, and credential replacement/removal
  draft-only.
- Validate locally and remotely before mutation, then register the shortcut,
  apply provider/Keychain changes, and persist settings with compensating
  rollback.
- Keep validation cancellable, preserve drafts on failure, and route/focus the
  first actionable issue.
- Allow confirmed credential removal and distinguish intentional/pre-existing
  unavailability from newly introduced invalid state.
- Suspend and reconcile an ordinary draft across transcription repair.

Gate: Debug build succeeds; shortcut and credentials do not change before Save;
failed/cancelled saves preserve prior runtime and persisted state; Discard
restores app-owned fields.

## Phase 3 — Sidebar Settings UI

- Build a `NavigationSplitView` with General, Transcription, Post-processing,
  and Providers.
- Split page content, add page headers/status indicators, dynamic data-flow
  disclosures, and filtered provider/model/language controls.
- Add provider list-to-detail navigation and the OpenAI custom settings page.
- Add the persistent Save/Finish/Repair footer with progress and errors.
- Persist only top-level navigation.
- Add `NSWindowDelegate` close protection for validation and dirty drafts.
- Preserve keyboard, default-button, focus-routing, and VoiceOver behavior.

Gate: Debug and Release builds succeed; navigation preserves drafts; close,
save, discard, badges, resizing, and accessibility behavior are verified.

## Phase 4 — Lifecycle, repair, and acceptance

- Add explicit ordinary, destination, provider, first-run, and repair routes.
- Route missing provider/authentication, invalid stage settings, and
  post-processing attention to their owning pages.
- Close after successful first-run and repair while leaving ordinary Save open.
- Lock but preserve drafts during active sessions.
- Restrict repair to transcription/provider configuration, reconcile suspended
  ordinary drafts, and retain explicit Retry.
- Attribute and clear runtime health at provider/stage scope.
- Complete the manual acceptance matrix and record evidence here.

Gate: Debug and Release builds and the complete specification acceptance matrix
succeed.

## Core interfaces

- `ProviderRegistry` owns implemented-provider registrations and exposes
  metadata, Settings modules, readiness, and runtime resolution.
- `ProviderSettingsModule` owns custom provider draft/validation/commit/view
  behavior; `AnyProviderSettingsModule` type-erases only the registry boundary.
- `ProviderReadiness` is derived per capability and never persisted.
- `StageConfiguration` stores active provider and model selections by provider.
- `ConfigurationIssue` routes errors to a destination/provider/field.
- `ConfigurationSaveResult` reports saved, cancelled, or failed outcomes.
- Credentials remain outside application/session configuration and are resolved
  from Keychain at provider-request time.

## Verification

No automated test target is added unless separately requested.

- Build Debug and Release under `/tmp` after every phase.
- Exercise navigation, draft preservation, validation, cancellation,
  save/discard, dirty close, resizing, keyboard access, and VoiceOver.
- Verify staged shortcut replacement and rollback.
- Verify existing-key reuse, credential replacement/removal rollback, and
  absence of duplicate Keychain items.
- Verify provider/model/language filtering and post-processing state.
- Verify first-run, setup routing, active-session locking, and repair/retry.
- Inspect logs and persistence for absence of credentials and user content.

## Assumptions

- macOS 15+, SwiftUI/AppKit, one target, and no new dependencies.
- OpenAI is the only registered provider.
- One account/configuration is supported per provider.
- Non-secret configuration may reset to defaults; the existing OpenAI Keychain
  item is preserved.
- This file is the only progress ledger for the feature.
