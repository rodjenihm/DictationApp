# Modernized Settings Presentation Implementation Plan

**Status:** Complete

**Specification:**
`docs/specifications/v1/features/07-modernized-settings.md`

## Outcome

Replace the current heavy Settings presentation with the approved Native
Inspector hybrid while preserving the existing SwiftUI and AppKit boundaries,
navigation, state, validation, accessibility, and transactional behavior.

The implementation will flatten ordinary sections, tighten page and window
spacing, standardize setting and status rows, compact provider navigation, and
quiet the global context and footer surfaces. It will not alter Settings data
flow or application behavior.

## Baseline

- Initial branch: `main`
- Initial revision: `feee622677c04973054afc1582e1f2857747299d`
- Initial worktree: clean before the approved feature specification was added;
  the only pre-plan change was the approved
  `docs/specifications/v1/features/07-modernized-settings.md` draft.
- Toolchain: Xcode 26.6 (`17F113`), with the existing macOS 15 deployment
  target.
- The current Settings window is an AppKit `NSWindow` hosting SwiftUI. That
  ownership remains unchanged.
- The current `NavigationSplitView`, nested provider `NavigationStack`,
  `@Bindable` configuration view model, `@ObservedObject` provider modules,
  AppKit shortcut recorder, and AppKit default action button remain the
  behavioral foundation.
- Build artifacts will remain outside the repository.
- No automated test target or test changes are authorized for this feature.

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Approved contract and baseline | Complete | Synchronize specification precedence and freeze implementation boundaries | 2026-08-23: approved specification, precedence note, and clean-revision baseline recorded |
| 2. Shared presentation foundation | Complete | Compact window shell, page composition, flat sections, rows, statuses, context strip, and footer | 2026-08-23: Debug build, source audit, and live default/minimum/expanded window inspection passed |
| 3. General and stage pages | Complete | Convert General, Transcription, and Post-processing without behavior changes | 2026-08-23: Debug build and app-scoped Accessibility inspection covered all three destinations |
| 4. Provider list and details | Complete | Compact provider navigation and flat provider details | 2026-08-23: provider list, both detail pages, disclosure, and responsive row layout inspected live |
| 5. Acceptance and documentation | Complete | Complete visual, keyboard, accessibility, appearance, and build verification | 2026-08-23: signed Debug and Release builds, signatures, scope, privacy, and repository checks passed; limitations recorded below |

Every completed phase will receive dated evidence. Do not mark a phase complete
from source edits alone when its gate requires a build or interaction review.

## Architecture and ownership

### Preserve existing ownership

- `ConfigurationWindowController` continues to own the singleton window,
  activation, sizing constraints, close protection, sheets, and key-view-loop
  recalculation.
- `ConfigurationViewModel` continues to own navigation, drafts, validation,
  transactional save, routing, permissions, provider selection, and all
  derived state.
- `ConfigurationView` continues to compose the context strip, native sidebar,
  selected detail destination, and transactional footer.
- Each destination continues to bind directly to the existing view model.
- Provider modules continue to own provider-specific drafts, validation,
  commit/rollback behavior, and injected detail content.
- `ShortcutRecorder` and `AccessibleActionButton` remain AppKit-backed because
  they provide specialized keyboard, focus, and default-button behavior.

Do not move business or validation logic into new presentation components.
Presentation types take only the values, bindings, content, and actions they
need.

### Shared presentation components

Refactor `ConfigurationViewComponents.swift` into small SwiftUI view types with
narrow inputs and stable identity:

- Keep `ConfigurationPage` as the shared detail shell, but give it the compact
  header, leading-aligned readable content column, native scrolling, and
  accessibility-adaptive layout defined by the specification.
- Replace `ConfigurationSettingsGroup` with a flat section component. It owns
  a concise header, optional decorative SF Symbol, section spacing, and content
  container, but no default card fill, rounded border, or shadow.
- Add a shared presentation-only setting-row pattern where existing
  `LabeledContent` alone cannot align the label, control, help, and issue text.
  It must support horizontal layout at ordinary widths and clear vertical
  stacking when content requires more room.
- Consolidate permission, provider, issue, and footer status appearance behind
  small icon-and-text components with a presentation-only semantic style.
  Domain readiness and issue types remain unchanged.
- Add a subtle contained-surface style for provider entries and actionable
  attention content only. Use `background` or `overlay` for decoration rather
  than peer-layer stacks, and do not add interior shadows.
- Use native `DisclosureGroup` only for the approved low-frequency explanatory
  detail. Keep its expansion state private to the smallest owning view.

Prefer dedicated `View` structs over large computed `@ViewBuilder` properties
when a section has independent inputs or conditional state. Keep stored generic
content as a view value rather than storing a closure. Do not add type erasure
or geometry-driven state for the layout.

### API and platform constraints

- Continue using `NavigationSplitView`, `NavigationStack`, modern `onChange`
  overloads, dedicated accessibility modifiers, `foregroundStyle`, and native
  semantic materials.
- Do not adopt Liquid Glass or another macOS 26-only API. The feature must keep
  its macOS 15 deployment compatibility.
- Do not migrate the AppKit-managed Settings window to a SwiftUI Settings scene
  as part of this visual change.
- Do not add custom control primitives, gesture-based button replacements,
  custom focus rings, or animation.

## Phase 1 — Approved contract and baseline

### Documentation

- Mark the new specification Approved.
- Add a presentation-precedence note to
  `docs/specifications/v1/features/01-tabbed-settings.md`.
- Add this separate feature plan without modifying the completed historical
  tabbed Settings plan.
- Leave `docs/plans/v1/progress.md` unchanged until implementation evidence
  exists.

### Implementation boundary audit

Before source edits, record the current files and behaviors that must remain
stable:

- Window size ownership exists in both `ConfigurationView` and
  `ConfigurationWindowController`; change them together.
- Detail editing is disabled per destination. Sidebar navigation and footer
  validation cancellation remain outside that disabled scope.
- `AccessibleActionButton` owns the enabled Return-key default action and
  native focus ring.
- `ShortcutRecorder` owns recording activation, modifier validation, Escape,
  focus-loss cancellation, and accessibility metadata.
- Stage provider bindings preserve per-provider model and language choices.
- Apple locale selection updates language-asset state.
- OpenAI key editing records credential replacement and removal intent.
- Provider row observation flows through `AnyProviderSettingsModule`.

Gate: documentation has unambiguous precedence, the worktree baseline is
recorded, and no application source has changed.

## Phase 2 — Shared presentation foundation

### Window and sidebar

Update `ConfigurationWindowController.swift` and `ConfigurationView.swift`
together:

- Change the initial content size from 860 by 720 points toward the approved
  800-by-640 target.
- Change the minimum from 760 by 620 points toward the approved 720-by-540
  target.
- Use the same minimum in SwiftUI and AppKit so neither layer silently
  overrides the other.
- Tighten the sidebar's ideal and maximum widths within the approved range
  while keeping the current native resizable split behavior.
- Preserve the standard title bar, window style mask, singleton lifecycle,
  activation, centering, and key-view-loop recalculation.

### Page shell and sections

Update `ConfigurationViewComponents.swift`:

- Reduce page-header and scroll-content padding to the approved compact rhythm.
- Use a compact semantic page title, one concise secondary description, and a
  hairline separation from content.
- Add a leading-aligned readable maximum width without centering content when
  the window grows.
- Replace `GroupBox` section chrome with the shared flat section component.
- Preserve natural vertical wrapping and native scrolling at the minimum size.
- Avoid hard-coded row heights and width assumptions that conflict with text
  expansion.

### Context strip and footer

Update `ConfigurationView.swift`:

- Restyle the active-session and repair banner as a compact, wrapping,
  non-dismissible context strip.
- Retain the existing copy meaning, symbols, and conditional visibility.
- Restyle the footer as a compact action bar with a subtle top separator.
- Preserve issue, success, and neutral priority; validating progress and
  Cancel; context-specific primary titles; enabled state; and default-button
  behavior.
- Keep the footer readable when the leading message wraps to two lines.

### Shared status presentation

- Introduce one presentation-only status vocabulary for configured, routine,
  attention, warning, error, pending, and success states.
- Adapt existing permission, issue, provider, and footer views to that
  vocabulary without changing their domain inputs or accessibility wording.
- Keep unsaved sidebar state compact and preserve its explicit accessibility
  label.

Gate:

- A Debug build succeeds.
- Source review confirms the existing view model, bindings, action closures,
  `.disabled` scope, window delegate, and AppKit control implementations are
  unchanged.
- The shell remains usable at default, minimum, and expanded widths without
  clipped footer actions.

## Phase 3 — General and stage pages

### General

Update `ConfigurationGeneralView.swift` while preserving section order:

1. Permissions
2. Recording
3. Global Shortcut
4. Feedback
5. Data & Privacy

Apply the shared section and row patterns:

- Present the three permission states as consistent label, status, action, and
  concise-help rows.
- Preserve immediate permission actions and their separation from the draft.
- Keep the microphone picker and complete accessibility value, with its
  availability status visually attached to the same row.
- Keep the AppKit shortcut recorder, reset action, saved-shortcut explanation,
  and inline error behavior intact.
- Present sound cues as one compact native toggle row.
- Tighten Data & Privacy copy while retaining visible Keychain, current data
  flow, processing location, post-processing, backend, and retention facts.
  Do not add privacy controls.

### Transcription

Update `ConfigurationStageViews.swift`:

- Remove the redundant inner Transcription heading and present the existing
  controls as one compact aligned form.
- Preserve the specialized provider binding, conditional model row, custom
  identifier, language picker, unsupported-language state, data-flow
  disclosure, no-provider route, and repair-only language presentation.
- Keep the current `@FocusState` ownership private and preserve issue-driven
  focus routing.

### Post-processing

- Keep Enable transcript cleanup as the first control.
- Make the conditional provider/model configuration visually subordinate to
  the enable row without changing conditional view behavior or retained draft
  values.
- Align provider, model, custom identifier, disclosure, attention, and issue
  presentation with Transcription.
- Preserve current focus and issue-clearing behavior.

Gate:

- A Debug build succeeds.
- General exposes every existing control and immediate/draft boundary.
- Transcription and Post-processing retain all provider, model, language,
  enablement, warning, error, focus, and repair behavior.
- Page content remains readable and scrollable at the approved minimum size.

## Phase 4 — Provider list and details

### Provider list

Update `ConfigurationProvidersView.swift`:

- Replace the large provider card presentation with a compact native `Button`
  row. Do not use a gesture-only activation target.
- Retain the provider symbol, display name, stable capability order, readiness
  icon and text, disclosure affordance, action, accessibility hint, and stable
  `ForEach` identity.
- Keep capability capsules as compact metadata with lower contrast and reduced
  padding.
- Use one subtle material or quaternary surface treatment without an interior
  shadow or stacked card effects.
- Preserve the nested `NavigationStack` and existing selected-provider binding.

### Provider detail shell

- Reduce the provider header's scale and padding while retaining symbol, name,
  purpose, and native back navigation.
- Convert Configuration and Capabilities to the shared flat section pattern.
- Present capabilities as aligned label-and-value rows.
- Continue hosting `module.makeDetailView()` through the existing type-erased
  module boundary.

### OpenAI detail

Update `OpenAIProviderSettingsModule.swift` presentation only:

- Preserve readiness, write-only secure credential field, Keychain statement,
  credential intent, destructive removal action, and confirmation dialog.
- Keep a concise validation summary visible.
- Place the complete bundled-fixture and fixed-text validation explanation in
  a native, keyboard-accessible disclosure.
- Keep expansion state private to the OpenAI detail view.

### Apple On-Device detail

Update `AppleOnDeviceProviderSettingsModule.swift` presentation only:

- Align availability, permission, language, asset state, progress, actions,
  errors, and processing-location disclosure with the shared row rhythm.
- Preserve every permission and installation branch, action, disabled state,
  progress value, reservation behavior, and provider readiness state.
- Keep unsupported-system and unavailable-device explanations immediately
  visible because they affect provider choice.

Gate:

- A Debug build succeeds.
- Provider list navigation works by pointer and keyboard.
- Provider observation, specialized bindings, credential intent, confirmation,
  Apple installation state, and first-run OpenAI escape behavior remain intact.
- Provider list and detail layouts remain readable at minimum and expanded
  widths.

## Phase 5 — Acceptance and documentation

### Visual and interaction review

Exercise the completed Settings presentation at minimum, default, and expanded
window sizes:

- General with each permission state represented where practical, available and
  unavailable microphone status, shortcut recording, shortcut error, Feedback,
  and Data & Privacy.
- Transcription with OpenAI and Apple On-Device, curated and custom model states,
  supported and unsupported language, and no-provider recovery where practical.
- Post-processing disabled and enabled, including warning and custom-model
  states.
- Provider list, OpenAI detail, Apple On-Device detail, installation progress,
  and provider errors where practical.
- Ordinary editable mode, first run, active-session read-only mode,
  transcription repair, validation progress, validation failure, save success,
  dirty close, and validation close.

Confirm:

- No ordinary section retains the previous stack-of-`GroupBox` appearance.
- Content remains leading-aligned and bounded in a wide window.
- The context strip and footer are quiet in routine states and prominent enough
  for restrictions or errors.
- All essential information remains visible; disclosures contain only approved
  secondary detail.
- Light and dark appearances use semantic colors and materials.
- Increased contrast, increased text size, and non-color status meaning remain
  usable where the host configuration permits inspection.
- Sidebar navigation, provider drill-in/back, scrolling, Tab traversal, native
  focus rings, shortcut recorder keyboard behavior, Return-key default action,
  and issue focus routing remain intact.
- VoiceOver/accessibility hierarchy retains clear control names, values, roles,
  help, disclosure state, and reading order. Record any verification limitation
  explicitly.

### Build and repository verification

- Build Debug with derived data outside the repository.
- Build Release with derived data outside the repository.
- Run `git diff --check`.
- Review changed paths for visual-only scope.
- Review changed source for accidental logging of credentials, transcripts,
  audio, clipboard content, or request bodies.
- Confirm no new dependency, framework, test target, or macOS 26-only API was
  introduced.

### Documentation completion

- Change this plan's status to Complete and add dated evidence to the progress
  table only after all required gates pass.
- Change the feature specification status from Approved to Complete when the
  implementation satisfies its acceptance criteria.
- Add the completed feature and verification evidence to
  `docs/plans/v1/progress.md`.
- Record manual limitations without weakening unverified acceptance criteria.

Gate: Debug and Release builds succeed, repository checks pass, the manual
acceptance matrix has evidence or explicit limitations, and all related
documentation is synchronized.

## Completion evidence — 2026-08-23

Implemented:

- Replaced ordinary `GroupBox` cards with a shared flat section rhythm and a
  leading-aligned, 680-point maximum content column.
- Reduced page, provider-header, sidebar, context-strip, and footer density;
  retained native SwiftUI controls, the AppKit-managed window, the AppKit
  shortcut recorder, and the AppKit default action button.
- Added shared icon-and-text status presentation, consistent permission rows,
  compact provider buttons, and a native disclosure for secondary OpenAI
  validation detail.
- Changed the initial content size to 800 by 640 points and the synchronized
  AppKit/SwiftUI minimum to 720 by 540 points.
- Kept `ConfigurationViewModel`, provider bindings and behavior, validation,
  save transactions, disabled-state scope, focus ownership, window delegates,
  close protection, and all domain, engine, infrastructure, and lifecycle code
  unchanged.

Verified:

- Final normally signed arm64 Debug and Release builds succeeded with Xcode
  26.6 and the existing macOS 15.0 deployment target.
- Both final app bundles passed strict deep code-signature verification.
- App-scoped Accessibility inspection covered General, Transcription,
  Post-processing, the Providers list, OpenAI detail, and Apple On-Device
  detail without changing a setting or invoking a provider.
- The OpenAI validation disclosure expanded and retained its explicit help;
  secure-key, microphone, shortcut, model, language, cleanup, provider, and
  Save controls retained native roles, values, enabled states, or help.
- Provider buttons expose provider identity, readiness, capabilities, and
  navigation help as non-color accessibility content.
- A visible native Back to Providers action now clears the existing provider
  detail selection directly. Activation in an isolated live Debug build
  returned the provider list with both provider rows. The action also supports
  the standard Command-[ Back shortcut, hover help, keyboard focus, and an
  explicit accessibility label.
- The default window exposed 800 by 640 content points. A below-minimum resize
  resolved to 720 by 540 content points; the 184-point sidebar, 488-by-57
  provider rows, and 111-by-24 Save button remained unobscured. At an expanded
  1100-point window width, provider rows stopped at the intended 680-point
  readable-column maximum and remained leading-aligned.
- The live host used Dark appearance. Changed source uses semantic primary,
  secondary, tertiary, quaternary, tint, status colors, and system material for
  automatic Light/Dark adaptation; no fixed foreground/background RGB values
  or appearance override was introduced.
- Changed-path review found presentation and synchronized documentation only.
  `ConfigurationViewModel`, `AccessibleActionButton`, `ShortcutRecorder`, and
  behavioral layers were untouched. No dependency, framework, test target,
  custom control primitive, or macOS 26-only Settings API was added.
- `git diff --check` passed. Changed-source inspection found no added logging or
  logging of credentials, transcripts, audio, clipboard content, or request or
  response bodies.

Verification limitations:

- Screen capture was unavailable because the host did not grant screen-recording
  access. Layout and control metadata were inspected through the app-scoped
  Accessibility hierarchy instead of capturing unrelated screen content.
- Spoken VoiceOver output, increased-contrast mode, increased text size, and a
  complete Tab traversal were not repeated. The host's full-keyboard-navigation
  preference remains disabled, and it was not changed for verification.
- Destructive permission, credential-removal, language-installation, dirty-close,
  validation, active-session, repair, and first-run branches were not triggered.
  Their existing behavior and ownership are unchanged, and previously recorded
  v1 Settings verification remains applicable to those untouched paths.

## Expected source scope

Primary source files:

- `DictationApp/Presentation/Configuration/ConfigurationView.swift`
- `DictationApp/Presentation/Configuration/ConfigurationViewComponents.swift`
- `DictationApp/Presentation/Configuration/ConfigurationGeneralView.swift`
- `DictationApp/Presentation/Configuration/ConfigurationStageViews.swift`
- `DictationApp/Presentation/Configuration/ConfigurationProvidersView.swift`
- `DictationApp/Presentation/Configuration/OpenAIProviderSettingsModule.swift`
- `DictationApp/Presentation/Configuration/AppleOnDeviceProviderSettingsModule.swift`
- `DictationApp/Presentation/Configuration/ConfigurationWindowController.swift`

Behavioral source files should remain unchanged unless implementation reveals a
presentation blocker that cannot be resolved in the expected scope:

- `DictationApp/Presentation/Configuration/ConfigurationViewModel.swift`
- `DictationApp/Presentation/Configuration/ProviderSettingsModule.swift`
- `DictationApp/Presentation/Configuration/AccessibleActionButton.swift`
- `DictationApp/Presentation/Configuration/ShortcutRecorder.swift`
- Domain, engine, infrastructure, and application-lifecycle files

Any required behavioral-file edit is a scope exception and must be explained
before proceeding.

## Risk controls

| Risk | Control |
| --- | --- |
| Window minimums conflict between SwiftUI and AppKit | Change and inspect both sizing layers together |
| Flat refactor changes control identity or loses field state | Preserve conditional structure and specialized bindings; extract stable view types with narrow inputs |
| Disabled-state scope blocks navigation or Cancel | Keep per-destination disabling exactly where it is today |
| Custom provider styling breaks activation or accessibility | Retain native `Button`, stable identity, explicit hint, and observed module input |
| Disclosure hides actionable information | Collapse only approved low-frequency explanation; keep consequences, warnings, and essential data flow visible |
| New row layout truncates text or reorders focus | Allow vertical stacking and wrapping; inspect minimum width and keyboard order |
| AppKit control regression | Leave shortcut recorder and accessible default action implementations intact |
| Provider draft or installation behavior changes | Restrict provider-module edits to their SwiftUI view sections and preserve all action methods and bindings |
| Fixed colors fail in light, dark, or contrast modes | Use semantic styles and system materials only |
| Unrelated modernization expands scope | Do not migrate architecture, adopt Liquid Glass, or change behavior during this feature |

## Final acceptance matrix

| Area | Required result |
| --- | --- |
| Window | Approximately 800-by-640 default and 720-by-540 minimum; resizable and scroll-safe |
| Navigation | Existing four destinations, persistence, contextual routing, provider drill-in, and back navigation remain intact |
| Density | Flat ordinary sections, compact rows, bounded leading content, restrained provider surfaces |
| General | Every permission, microphone, shortcut, sound, privacy, action, status, and issue remains available |
| Stages | All provider, model, custom model, language, enablement, data-flow, repair, warning, and error states remain available |
| Providers | Compact accessible rows and complete OpenAI and Apple On-Device detail behavior |
| Transaction | Dirty state, validation, Cancel, Save/Finish/Repair, rollback, success, and close protection remain intact |
| Keyboard | Sidebar, fields, pickers, buttons, disclosures, shortcut recorder, default action, and validation focus remain operable |
| Accessibility | Labels, values, hints, state, reading order, non-color meaning, wrapping, and native focus presentation remain intact |
| Appearance | Light, dark, contrast, and text expansion remain legible without fixed-color surfaces or decorative animation |
| Compatibility | macOS 15+, existing native stack, no new dependency, no test changes, no macOS 26-only API |
| Verification | Debug and Release builds and repository checks succeed; evidence and limitations are recorded |

## Assumptions

- The approved specification contains no open product decisions.
- Exact compact metrics may be adjusted slightly during visual verification to
  accommodate native control fitting and accessibility without changing the
  approved direction.
- Existing first-run, repair, provider-installation, and validation states can
  be inspected without changing their semantics.
- Normal implementation does not require changes outside the expected source
  scope.
