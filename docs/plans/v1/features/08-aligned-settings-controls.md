# Aligned Settings Controls Implementation Plan

**Status:** Complete

**Specification:**
`docs/specifications/v1/features/08-aligned-settings-controls.md`

## Outcome

Introduce one shared Settings form grid, migrate the applicable controls and
supporting content to it, and preserve native macOS control behavior. The
completed implementation uses a 128-point label column, a 14-point column gap,
and a 220-point editable-control width.

This plan was added retroactively after implementation and verification. It
records the boundary, decisions, and evidence that governed the completed
feature rather than presenting unfinished future work.

## Retrospective baseline

- Branch: `main`
- Base revision: `1c13362d7dc498262e0869383232ea0c067d1711`
  (`Modernize Settings presentation`)
- Feature 07 was complete at the base revision and supplied the flat Settings
  hierarchy that this feature refines.
- The feature 08 source edits were present as uncommitted presentation changes
  when this missing specification and plan were added.
- Toolchain: Xcode 26.6 (`17F113`), with the existing macOS 15 deployment
  target.
- Build artifacts and live-inspection products remained outside the repository.
- No automated test target or test changes were authorized or added.

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Form contract | Complete | Defined the shared grid, native-sizing boundary, accessibility adaptation, and preserved behavior | 2026-08-24: retrospective specification synchronized with the implemented contract |
| 2. Shared components | Complete | Added centralized row, supplementary-content, field-width, and picker-sizing presentation helpers | 2026-08-24: source inspection and Debug build passed |
| 3. Settings migration | Complete | Applied the shared layout across stage, General, provider-list, and provider-detail forms | 2026-08-24: app-scoped Accessibility geometry confirmed live alignment |
| 4. Compatibility and verification | Complete | Preserved macOS 15 fallback and verified both build configurations, scope, and repository hygiene | 2026-08-24: Debug and Release builds and `git diff --check` passed |

## Architecture

`ConfigurationViewComponents.swift` owns the presentation contract:

- `ConfigurationFormMetrics` centralizes the 128-point label width, 14-point
  gap, and 220-point field width.
- `ConfigurationSettingRow` composes the label and value columns, aligns their
  first text baselines, and stacks them at accessibility text sizes.
- `ConfigurationFormSupplementary` aligns independent help or issue content
  with the value column and removes the indent at accessibility text sizes.
- `configurationFieldControl()` applies the shared field width and regular
  native control size.
- `configurationPickerControl()` adds macOS 26 flexible button sizing behind an
  availability check before applying the field width.

Destination views adopt these components without moving state or behavior.
`ConfigurationViewModel`, provider modules' action methods, specialized AppKit
controls, and all domain, engine, infrastructure, and lifecycle layers retain
their existing ownership.

## Implementation phases

### Phase 1 — Form contract

- Classify setting content as a field-like control, natural-width value,
  standalone checkbox, action, or supporting content.
- Set one ordinary horizontal grid and define vertical stacking for
  accessibility text sizes.
- Keep width and column alignment standardized while leaving height and focus
  presentation to native controls.
- Record behavior, compatibility, and scope exclusions before final handoff.

Gate: the contract standardizes comparable controls without stretching native
elements that have different semantics.

### Phase 2 — Shared components

- Add centralized form metrics to `ConfigurationViewComponents.swift`.
- Add a reusable setting row with label and value columns.
- Add a supplementary-content wrapper that shares the value-column origin.
- Add field and picker modifiers so destinations cannot drift independently.
- Gate macOS 26 picker sizing while retaining the macOS 15 fallback.

Gate: shared components own all repeated layout values, compile against the
existing deployment target, and contain no state or domain behavior.

### Phase 3 — Settings migration

- Migrate provider, model, custom-model, language, and related issue content in
  Transcription and Post-processing.
- Migrate General microphone selection and permission rows.
- Migrate provider capabilities and OpenAI and Apple On-Device detail forms.
- Align field disclosures and explanations through the supplementary-content
  wrapper.
- Keep enablement checkboxes as native standalone rows.

Gate: every scoped destination uses the shared grid where applicable, while
bindings, actions, validation, navigation, and accessibility metadata remain
unchanged.

### Phase 4 — Compatibility and verification

- Build Debug and Release with the macOS 15 deployment target.
- Inspect representative enabled Settings pages through the macOS
  Accessibility hierarchy.
- Compare picker origins and dimensions and confirm supporting-text alignment.
- Review changed paths for presentation-only scope and changed source for
  privacy-sensitive logging.
- Run `git diff --check` and synchronize the specification, plan, and progress
  ledger.

Gate: both builds pass, representative live controls share the required
geometry, behavior layers remain untouched, and limitations are recorded.

## Expected source scope

- `DictationApp/Presentation/Configuration/ConfigurationViewComponents.swift`
- `DictationApp/Presentation/Configuration/ConfigurationGeneralView.swift`
- `DictationApp/Presentation/Configuration/ConfigurationStageViews.swift`
- `DictationApp/Presentation/Configuration/ConfigurationProvidersView.swift`
- `DictationApp/Presentation/Configuration/OpenAIProviderSettingsModule.swift`
- `DictationApp/Presentation/Configuration/AppleOnDeviceProviderSettingsModule.swift`
- `docs/specifications/v1/features/08-aligned-settings-controls.md`
- `docs/plans/v1/features/08-aligned-settings-controls.md`
- `docs/plans/v1/progress.md`

No domain, engine, infrastructure, application-lifecycle, project, dependency,
or test file belongs to the feature scope.

## Risk controls

| Risk | Control |
| --- | --- |
| Fixed widths clip enlarged content | Stack rows at accessibility text sizes and allow supporting copy to wrap |
| Every element is stretched indiscriminately | Limit the field width to editable controls; retain natural sizing for statuses, actions, and checkboxes |
| macOS 26 pickers ignore the shared frame | Apply native flexible button sizing behind an availability check |
| New SDK behavior raises the deployment target | Keep the modifier in a macOS 26 availability branch and compile both configurations for macOS 15 |
| Migration changes bindings or validation | Restrict edits to view composition and reuse all existing bindings, focus targets, and actions |
| Supporting text appears detached | Align related details and independent form help to the value-column origin |

## Verification matrix

| Area | Expected result |
| --- | --- |
| Transcription | Provider, Model, and Language pickers share a 220-point width and origin; processing detail aligns beneath them |
| Post-processing | Enabled Provider and Model pickers share a 220-point width and origin; enablement remains a standalone checkbox |
| General | Microphone picker uses the field width; permission values and explanations share the value column |
| Providers | Capabilities use the shared label/value columns without stretching their text |
| OpenAI | Status and API-key content use the shared grid; credential actions retain native sizing |
| Apple On-Device | Status, language, language asset, issues, and explanations use the shared grid where applicable |
| Accessibility | Rows stack vertically at accessibility text sizes without clipping supporting content |
| Compatibility | macOS 26 picker adjustment is availability-gated and the product still targets macOS 15 |

## Verification evidence

- 2026-08-24: Normally signed Debug and unsigned Release builds succeeded with
  Xcode 26.6 and the macOS 15 deployment target.
- 2026-08-24: A normally signed inspection build with an isolated product name
  and bundle identifier exposed the final Settings hierarchy through app-scoped
  macOS Accessibility.
- 2026-08-24: Transcription Provider, Model, and Language pop-up buttons shared
  horizontal origin 710 and measured 220 by 24 points. Processing-location text
  began beneath the same control column.
- 2026-08-24: Enabled Post-processing Provider and Model pop-up buttons shared
  horizontal origin 710 and measured 220 by 24 points. The enable checkbox
  remained a conventional standalone row.
- 2026-08-24: The General microphone pop-up button measured 220 by 24 points;
  permission values and explanations shared the control column.
- 2026-08-24: Changed-path review found presentation and synchronized
  documentation only. No behavior, provider binding, validation, persistence,
  dependency, framework, test, or privacy-sensitive logging change was added.
- 2026-08-24: `git diff --check` passed before the final documentation update.

## Verification limitations

- Screen capture remained unavailable because the host has not granted screen
  recording access. App-scoped Accessibility geometry was used for live layout
  verification without reading unrelated screen content.
- Accessibility Dynamic Type stacking was verified from the shared conditional
  layout and both builds, not by changing the user's system text-size setting.
- Runtime compatibility was not exercised on a macOS 15 machine or virtual
  machine; availability guarding, deployment metadata, and compilation provide
  the compatibility evidence available on the macOS 26 host.

## Assumptions

- The feature 07 window minimum remains in force and provides enough ordinary
  width for the grid.
- Native control height may vary by macOS release; width and alignment are the
  cross-version contract.
- The base revision and dirty-worktree note are the retrospective equivalent of
  a pre-implementation baseline because the documentation was requested after
  the code and verification were complete.
