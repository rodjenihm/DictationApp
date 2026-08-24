# Aligned Settings Controls

**Status:** Complete

## Summary

Standardize the label, control, and supporting-text alignment in DictationApp
Settings. Field-like controls use one visual width and one leading edge, while
native checkboxes, status values, and action buttons keep their conventional
macOS sizing.

This specification refines the form-layout requirements in
`07-modernized-settings.md`. That specification remains authoritative for the
overall Settings presentation. This document governs the form grid, field
widths, supporting-text alignment, and platform-specific picker sizing.

## Motivation

The modernized Settings window established a compact hierarchy, but individual
rows still relied on each control's intrinsic width. Picker width therefore
varied with the selected value, labels did not form one predictable column, and
help text did not consistently begin beneath its related control. The result
looked accidental even though every control was individually native.

macOS Settings forms benefit from shared alignment, but they should not copy a
web form's rigid box model. Width and column position should be standardized;
height, focus presentation, and interaction geometry should remain native.

## Goals

- Give comparable editable controls the same width and leading edge.
- Give ordinary setting labels a consistent leading-aligned column.
- Align field help, validation, warnings, and processing disclosures beneath
  the value column.
- Preserve native control heights, roles, focus rings, and interaction.
- Retain a readable stacked layout at accessibility text sizes.
- Apply the same form language across stage, General, provider-list, and
  provider-detail content.
- Preserve macOS 15 deployment compatibility while correcting macOS 26 picker
  sizing through an availability-gated native API.

## Non-goals

- Make every element the same width or height.
- Stretch standalone checkboxes, status text, permission actions, disclosure
  controls, or ordinary buttons to the editable-field width.
- Replace `Picker`, `TextField`, `SecureField`, `Toggle`, or `Button` with a
  custom control.
- Change Settings navigation, window dimensions, section hierarchy, copy,
  validation, persistence, provider behavior, or save transactions.
- Add responsive geometry measurement, a third-party dependency, or a custom
  layout engine.
- Require macOS 26 or change the macOS 15 deployment target.
- Add or change automated tests.

## Form layout contract

At ordinary Dynamic Type sizes, a setting row uses three shared measurements:

- A 128-point label column.
- A 14-point gap between the label and value columns.
- A 220-point width for field-like controls.

Labels are leading-aligned within their column. The label and first value use
first-text-baseline alignment where the native controls expose one. A value may
include supporting content below it without changing the position of adjacent
rows.

The 220-point field width applies to editable controls that represent one
setting, including provider, model, language, and microphone pop-up buttons and
custom-model or credential text fields. Controls retain regular native control
sizing; the form does not impose a fixed height.

Read-only statuses and capabilities begin in the value column but keep their
natural width. Permission actions remain adjacent to their status. Standalone
checkbox rows keep the standard macOS checkbox composition because splitting a
checkbox label across the form grid would weaken its interaction semantics.

## Supporting content

Content that explains or validates a field begins at the value-column leading
edge when it is visually associated with the form:

- Help and processing-location text.
- Validation issues and compatibility warnings.
- Permission explanations.
- Provider availability and language-asset details.

Supporting content wraps naturally in the remaining page width. It must not be
constrained to the 220-point control width unless it is itself a field-like
control.

## Accessibility and adaptation

At accessibility Dynamic Type sizes, each setting row stacks vertically:

1. Label.
2. Control or value.
3. Supporting content.

Standalone supplementary content returns to the page's leading edge in this
mode. This removes the empty label-column indent and gives enlarged text the
available width.

The layout must preserve native accessibility roles, labels, values, hints,
keyboard order, and focus rings. Long content may wrap or expand the row; it
must not be clipped to preserve the ordinary layout metrics.

## Platform compatibility

On macOS 26, button-style pickers default to fitting their selected content.
Use the native flexible button-sizing behavior before applying the shared field
width so every picker occupies the full 220-point frame.

The picker sizing adjustment must be guarded with a macOS 26 availability
check. Earlier supported systems use their existing native behavior plus the
shared frame. No macOS 26 API may execute on macOS 15 through macOS 25.

## Scope

Apply the form contract to:

- General microphone selection and permission statuses.
- Transcription provider, model, custom model, language, issues, and processing
  disclosure.
- Post-processing provider, model, custom model, issues, and upload disclosure.
- Provider capability rows.
- OpenAI status and API-key fields.
- Apple On-Device status, language, asset status, issues, and explanations.

## Preserved behavior

The feature must not alter:

- Provider selection or per-provider model and language restoration.
- Custom-model, credential, permission, or language-asset actions.
- Validation routing, issue ownership, focus targets, or save eligibility.
- Draft, dirty-state, save, cancel, rollback, close-protection, and read-only
  behavior.
- Sidebar or provider-detail navigation.
- Accessibility metadata and specialized AppKit-backed controls.

## Acceptance criteria

- Comparable pickers and text-entry fields use the same 220-point visual width.
- Ordinary form controls share one value-column leading edge across a page.
- Ordinary labels share the 128-point label column and a consistent gap.
- Help, validation, warnings, and field disclosures align beneath the value
  column and wrap in the available width.
- Checkboxes, read-only text, and action buttons retain appropriate native
  sizing instead of being stretched indiscriminately.
- Comparable native controls retain consistent intrinsic heights without a
  custom fixed-height frame.
- Accessibility text sizes replace the horizontal grid with a clear vertical
  stack.
- macOS 26 pickers fill the intended width, and the availability-gated change
  preserves the macOS 15 deployment target.
- General, Transcription, Post-processing, Providers, OpenAI, and Apple
  On-Device use the shared form components where applicable.
- No Settings behavior, dependency, framework, test target, or privacy-sensitive
  logging changes.
- Debug and Release builds succeed, and live layout inspection confirms the
  expected alignment.

## Assumptions

- The approved Settings minimum width provides sufficient space for the
  128-point label column, 14-point gap, 220-point control, and page margins.
- Native control metrics may vary slightly by macOS release; shared width and
  alignment are required, while height remains platform-owned.
- Exact metrics may expand or stack when accessibility requires it.
