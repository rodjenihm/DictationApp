# Modernized Settings Presentation

**Status:** Complete

The [interface polish specification](14-interface-polish.md) governs the
current visual hierarchy and General section order.

## Summary

Modernize DictationApp's Settings presentation while retaining the existing
native SwiftUI and AppKit architecture, information architecture, controls,
and behavior.

The approved visual direction is a **Native Inspector hybrid**: compact,
aligned settings rows and restrained section hierarchy form the default
presentation, while subtle material-backed surfaces are reserved for provider
entries, warnings, and compact status summaries. The result should feel
recognizably macOS, visually related to the compact transcription overlay, and
distinctive through proportion and restraint rather than decorative branding.

This specification refines the visual presentation requirements in
`01-tabbed-settings.md`. The application specification and existing feature
specifications remain authoritative for Settings behavior. If this document
conflicts with them, this document governs only window sizing, spacing,
typography, section chrome, visual hierarchy, and information presentation.

## Motivation

The current Settings window has a sound behavioral foundation, but its visual
composition is heavier than the information requires:

- Each section uses a padded `GroupBox`, producing a stack of large cards.
- Page padding, section spacing, and repeated headings consume substantial
  vertical space.
- Provider entries use oversized card rows and capability pills.
- Help text, status labels, dividers, and actions do not follow one consistent
  alignment or density model.
- Content expands across the full detail width, reducing readability in a wide
  window.
- The global context banner and transactional footer are more prominent than
  their routine states warrant.

The compact transcription overlay established a quieter visual character based
on concise hierarchy, compact spacing, system materials, semantic colors, SF
Symbols, and native controls. Settings should share that restraint without
copying the overlay's floating capsule geometry or non-activating behavior.

## Goals

- Make every Settings destination faster to scan.
- Reduce the default and minimum window footprint without crowding controls.
- Establish consistent alignment for labels, controls, status, help, and
  validation messages.
- Preserve a clear distinction between ordinary configuration, status that
  needs attention, and consequential actions.
- Relate Settings visually to the compact overlay through density, materials,
  iconography, and restraint.
- Adapt naturally to light and dark appearances and macOS accessibility
  settings.
- Preserve all existing Settings behavior and native macOS conventions.

## Non-goals

- Change any setting, default, validation rule, save transaction, permission
  flow, provider capability, or runtime behavior.
- Add a destination, dashboard, search field, toolbar tab, navigation level,
  preference, onboarding flow, or overlay customization.
- Reorder the four top-level destinations or the General sections.
- Replace the native sidebar, provider drill-in, standard titled window, or
  persistent save workflow.
- Replace existing native controls with custom-drawn control equivalents.
- Introduce a cross-platform UI framework, third-party dependency, or macOS
  26-only visual API.
- Add decorative animation, branded gradients, oversized artwork, or
  web-style cards.
- Change the menu-bar UI or transcription overlay.
- Add or change automated tests.

## Design principles

### Native first

Use standard SwiftUI and AppKit controls, semantic text styles, SF Symbols,
system materials, system accent color, and native focus presentation. Custom
presentation may organize and style these controls but must not imitate their
behavior.

### Compact, not compressed

Reduce redundant padding and chrome before reducing control size or truncating
meaningful content. Controls must retain native interaction areas, focus rings,
keyboard behavior, and accessibility expansion.

### Flat by default

Use whitespace, alignment, concise section labels, and subtle separators to
organize ordinary settings. Do not place every section inside a rounded or
material-backed container.

### Emphasize exceptions

Reserve stronger surfaces and semantic color for information that benefits
from separation: provider entries, warnings, validation failures, permission
problems, and transient save status. Meaning must never depend on color alone.

### Quiet identity

Distinctiveness should come from consistent proportions, compact icon-and-text
status treatment, and selective material accents. Use the user's macOS accent
color rather than defining a fixed brand palette. Use the standard system font
for Settings; the overlay's rounded typography remains specific to the compact
floating presentation.

## Window and navigation

Retain the existing singleton, standard titled, closable, miniaturizable, and
resizable Settings window hosted by AppKit.

- Target an initial content size of approximately 800 by 640 points.
- Target a minimum size of approximately 720 by 540 points.
- Treat these dimensions as density goals, not hard accessibility caps. The
  window and content may require more space for accessibility text or system
  settings.
- Keep page content scrollable at the minimum size.
- Preserve one Settings window and activate the existing window when Settings
  is reopened.
- Preserve the native `NavigationSplitView` and one detail column.
- Keep the sidebar approximately 170 to 210 points wide, allowing native split
  view behavior to resolve the exact width.

The sidebar order remains:

1. General
2. Transcription
3. Post-processing
4. Providers

Each sidebar item retains its SF Symbol, visible label, selection state, and
non-color-only dirty, warning, or error indicator. Indicators should be compact
and visually consistent with detail-area statuses. VoiceOver must continue to
announce their meaning.

Do not add a landing page, Settings search, sidebar footer, or permanently
visible second navigation column. Provider configuration continues to drill
into the current detail area through native stack navigation.

## Detail-page composition

### Page header

Each top-level destination retains a title and one concise description.

- Use a compact semantic title style and semibold weight rather than a large
  display title.
- Keep the description to one line when the available width permits.
- Use secondary styling for the description.
- Separate the header from scrolling content with spacing or a hairline
  separator, not a card background or shadow.
- Avoid repeating the page title as the title of its only section.

Provider detail pages use the same header scale. Retain the provider symbol,
name, concise purpose statement, and native back navigation, but remove the
current oversized header treatment.

### Content column

Place scrollable content in a leading-aligned readable column.

- Use approximately 18 to 20 points of outer horizontal padding at standard
  sizes.
- Keep the ordinary content column approximately 640 to 680 points wide when
  additional window width is available.
- Do not center the content column; keep it aligned with the page title and
  the leading edge of the detail area.
- Let controls and explanatory text wrap vertically before forcing horizontal
  truncation.
- Preserve native scrolling and scroll indicators.

### Sections

Ordinary sections use a shared flat presentation:

- A concise section label, with an optional small SF Symbol when the symbol
  improves scanning.
- Compact vertical spacing between the section label and its rows.
- Consistent separation between adjacent sections.
- No default `GroupBox` border, rounded rectangle, fill, or shadow.
- Optional hairline separators between dense rows where alignment alone is
  insufficient.

Use a contained surface only when the content is a selectable object, a compact
status summary, or an actionable warning. Contained surfaces use a subtle
semantic material or quaternary fill, a fine separator or border when needed,
and a modest corner radius. Do not use interior drop shadows.

### Setting rows

Use one shared row rhythm across pages:

- Labels align in a stable leading column.
- Pickers, fields, status values, and row actions align in a trailing control
  column when space permits.
- Native controls retain their standard macOS control size unless a smaller
  native size remains fully legible and operable.
- A concise help or status line may appear below the primary row, aligned with
  the relevant label or control.
- Inline warnings and errors appear immediately below the affected control.
- Consequential or destructive actions remain labeled; do not replace them
  with ambiguous symbol-only controls.

At narrow or accessibility-expanded sizes, rows may stack their control below
the label. Reading order, focus order, and association between the label,
control, and help text must remain clear.

## Information hierarchy and disclosure

Keep information visible when it affects the current decision or explains a
consequence. This includes:

- Permission limitations and the capability affected by denial.
- Unavailable microphone, provider, model, language, or language asset state.
- Validation errors and warnings.
- Cloud versus on-device processing at the selected stage.
- Credential storage and destructive-removal consequences.
- Active-session, first-run, and transcription-repair restrictions.

Routine explanatory copy should be shortened to one concise nearby line.
Long, low-frequency explanations may use a native disclosure or help affordance
when all of the following are true:

- The collapsed presentation still states the essential behavior.
- The complete information remains available without leaving Settings.
- The disclosure is keyboard accessible and has an explicit accessibility
  label and state.
- An error, warning, or destructive consequence never becomes visible only
  after expansion.

Copy edits may remove repetition and tighten headings, labels, and help text.
They must preserve the original meaning, privacy guarantees, consequences, and
provider-neutral terminology.

## Global context strip

Preserve the existing active-session and transcription-repair explanations as
a global, non-dismissible context strip.

- Use compact vertical padding, a small SF Symbol, callout or caption text, and
  a subtle semantic background or separator.
- Keep the complete restriction understandable without relying on color.
- Allow the strip to wrap when required rather than truncate its meaning.
- Do not move the disabled state to the root view. Sidebar navigation and the
  footer's validation cancellation must remain available when detail editing
  is disabled.

The strip remains absent when no contextual restriction requires explanation.

## Persistent transactional footer

Retain the persistent footer and its existing status and actions. Present it as
a compact window-level action bar with a top separator and restrained material
or window background.

The leading status area retains this priority:

1. First validation issue
2. Save success
3. Neutral transactional or repair explanation

The trailing action area retains:

- Progress and Cancel while validation is running.
- The context-appropriate Save, Finish, or Repair action otherwise.
- Native default-button behavior for the primary action.

Use a compact icon-and-text status presentation. Errors, warnings, and success
must include text or an accessible equivalent and must not rely on color alone.
Long issues may wrap to a second line without displacing or obscuring the
primary action.

## Destination requirements

### General

Keep these sections in the existing order:

1. Permissions
2. Recording
3. Global Shortcut
4. Feedback
5. Data & Privacy

#### Permissions

Present Microphone, Accessibility, and Speech Recognition as aligned compact
rows. Each row retains its live status, contextual action, and concise
explanation. Permission actions remain immediate external-system actions and
must not appear to participate in the Settings draft.

Permission status uses one shared icon-and-text component. Enabled, denied,
restricted, and not-requested states remain understandable without color.

#### Recording

Keep the native microphone picker as the primary row and place its availability
or fallback status directly below it. Preserve the complete accessibility value
for the selected device, including visually truncated names.

#### Global Shortcut

Keep the AppKit-backed shortcut recorder as the primary control. Align the
saved-shortcut explanation with the same section rhythm.
Preserve local validation, focus behavior, Escape cancellation, and the fact
that the saved shortcut remains active until Save succeeds.

#### Feedback

Present the existing sound-cues toggle as one compact native row. Do not add
individual sound preferences or previews.

#### Data & Privacy

Provide a concise, configuration-aware summary of Keychain credential storage,
transcription processing location, post-processing state and processing
location, and DictationApp's lack of an account, proprietary backend, or
completed-session retention.

Keep the essential current data flow visible. Longer provider-validation or
privacy detail may use native disclosure when it satisfies the information
hierarchy requirements above. Do not introduce privacy toggles.

### Transcription

Remove the redundant inner section title when the page contains only the
transcription configuration. Present provider, conditional model, optional
custom model identifier, language, processing-location disclosure, and inline
issues as one compact aligned form.

Preserve:

- Provider-specific model restoration and filtering.
- Conditional omission of model selection when a provider does not expose it.
- Unsupported-language retention and warning.
- No-provider recovery navigation.
- Existing validation and error-focus routing.
- Restricted language presentation during transcription repair.

### Post-processing

Place Enable transcript cleanup first and give it clear ownership of the
conditional content below it. When disabled, show one concise explanation and
hide the provider and model controls exactly as today.

When enabled, align provider, model, custom model identifier, processing
location, attention state, and validation issues with the Transcription page.
Preserve all existing conditional state and draft restoration behavior.

### Providers

Present each implemented provider as a compact selectable native row rather
than a large card.

Each row retains:

- Provider SF Symbol and display name.
- Configuration readiness as icon and text.
- Declared capabilities.
- A disclosure chevron or equivalent native navigation affordance.
- Complete pointer, keyboard, and VoiceOver activation semantics.

Capability badges may retain a compact capsule shape because they are metadata,
not containers. Limit their padding and contrast so readiness and provider name
remain primary.

Use one subtle contained surface, native list-row separation, or selection
background to communicate row boundaries. Do not combine a heavy fill, border,
large radius, and shadow.

#### Provider detail

Use a compact provider header followed by flat Configuration and Capabilities
sections.

- OpenAI retains readiness, secure credential replacement, Keychain and
  validation disclosure, and staged destructive removal.
- Apple On-Device retains availability, permission, language, asset state,
  install progress and actions, errors, processing-location disclosure, and
  the first-run OpenAI escape action.
- Capabilities remain aligned label-and-value rows.
- Provider-owned SwiftUI detail content remains hosted through the existing
  provider-module boundary.

## Status presentation

Use one visual language for sidebar state, permission state, provider
readiness, field issues, and footer status:

- SF Symbol plus concise text where space permits.
- Semantic system colors for emphasis.
- Neutral secondary styling for routine states.
- Orange or warning semantics for attention and unsupported states.
- Red or error semantics for validation failures.
- Green or success semantics for confirmed configured or saved states.

Do not communicate state through a colored dot alone. A compact dot may still
represent unsaved changes when it retains the current explicit accessibility
label.

## Appearance and motion

- Support light, dark, and automatic appearances through semantic colors and
  system materials.
- Respect Increase Contrast and Differentiate Without Color by retaining
  symbols, labels, and sufficient separator definition.
- Let semantic text styles and flexible layouts accommodate increased text
  sizes.
- Add no decorative transitions, spring animations, hover scaling, or window
  resizing animation.
- Preserve ordinary native control, navigation, disclosure, focus, and
  selection feedback.
- Do not use the overlay's drop shadow inside the Settings content. The normal
  Settings window provides its own elevation.

## Accessibility and keyboard behavior

The redesign must preserve or improve the current accessibility contract:

- Every control retains an accessible name, value, role, state, and help text
  where the native label is insufficient.
- Reading order follows the visual top-to-bottom section order.
- Focus order follows navigation, page content, and the persistent footer
  without hidden or duplicate stops.
- The AppKit shortcut recorder retains click, keyboard, Escape, focus-loss,
  validation, and VoiceOver behavior.
- The primary footer action retains its native focus ring and Return-key
  default-button behavior only while enabled.
- Validation still routes to the owning destination and focuses the first
  supported actionable invalid field.
- Scrolling a page, resizing the window, opening a disclosure, or drilling into
  a provider must not lose or trap keyboard focus.
- Sidebar badges, statuses, disclosures, warnings, and errors remain
  understandable without color.

Do not apply overlay-specific non-focusable control behavior to Settings. The
Settings window is activating and must remain fully keyboard operable.

## Behavior preservation

The redesign must not alter:

- Draft creation, dirty-state calculation, validation, cancellation, commit,
  rollback, or save-success behavior.
- Permission action timing or system-derived permission status.
- Shortcut registration or rollback.
- Microphone preference identity, availability, or persistence.
- Provider selection, model restoration, language compatibility, capability
  filtering, readiness, credential intent, or provider validation.
- Provider module observation and custom detail injection.
- Ordinary destination persistence or contextual routing.
- First-run, active-session read-only, transcription-repair, and retained-draft
  reconciliation behavior.
- Close protection and save, discard, cancel, or validation-close sheets.
- Singleton window reuse, activation, key-window behavior, or key-view-loop
  recalculation.

Visual refactoring must not move `.disabled` to a scope that prevents sidebar
navigation or validation cancellation. Existing specialized bindings and
AppKit-backed controls must remain behaviorally intact.

## Documentation relationship

When this specification is approved:

- Add a presentation-precedence note to `01-tabbed-settings.md` that points to
  this document while retaining the older specification as the behavioral
  source of truth.
- Create a separate matching implementation plan under
  `docs/plans/v1/features/07-modernized-settings.md`.
- Do not rewrite the completed historical plan for tabbed Settings.
- Update `docs/plans/v1/progress.md` only as implementation and verification
  evidence becomes available.
- Update the application or other feature specifications only if implementation
  reveals a genuine behavior-level conflict.

## Acceptance criteria

- Settings opens in the approved compact size range and remains usable at its
  minimum size without clipped controls or inaccessible actions.
- The four existing destinations and provider drill-in remain unchanged.
- Ordinary sections no longer appear as a stack of padded `GroupBox` cards.
- Page headers, sections, rows, help, statuses, and issues follow one consistent
  visual hierarchy.
- Detail content remains leading-aligned and readable when the window becomes
  wider.
- Provider entries are compact, keyboard- and pointer-operable rows that retain
  name, capabilities, readiness, and navigation affordance.
- The context strip and footer remain persistent when applicable but are
  visually quieter in routine states.
- Long secondary explanations may collapse, while all actionable information
  and complete underlying detail remain available.
- General, Transcription, Post-processing, OpenAI, and Apple On-Device expose
  every existing control, state, action, warning, and disclosure.
- Dirty, warning, error, validating, success, read-only, repair, first-run, and
  provider-installation states remain legible and do not depend on color alone.
- Native keyboard navigation, default Save, shortcut recording, validation
  focus, close protection, scrolling, and provider navigation remain intact.
- Light and dark appearances use semantic colors and materials with no
  illegible fixed-color surfaces.
- Debug and Release builds succeed after implementation.
- Documentation precedence and implementation evidence are synchronized as
  defined above.

## Assumptions

- The deployment target remains macOS 15 or later.
- SwiftUI remains responsible for Settings content and AppKit remains
  responsible for the Settings window and specialized controls.
- The user's macOS accent color supplies interactive accenting.
- Exact spacing and dimensions may vary slightly where native control metrics
  or accessibility require it, provided the approved density and hierarchy are
  preserved.
- No automated test target or new dependency is introduced.
