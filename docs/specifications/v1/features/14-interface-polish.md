# Dictation interface polish

## Settings

Give the Settings window a distinct sidebar and a lighter content hierarchy.
Use an app mark and a consistent icon and title treatment across destinations
and provider details. Use neutral gray surfaces with clear separation between
the sidebar, canvas, and panels in both macOS appearances. Keep the native
window chrome and use the macOS accent for interactive selection and controls.
Use semantic colors for feedback such as errors and confirmed states.

On General, show a read-only summary of the microphone, transcription
provider, and cleanup provider in pipeline order. Reflect the values being
edited and identify them as draft values when Settings has unapplied changes.
Place the microphone and shortcut controls before routine permissions when
microphone access is ready. Give microphone permission priority when it needs
attention. Align the shortcut recorder with the microphone control. Let
permission actions move below their status when the row is narrow. Use the
existing provider and microphone display names.

Use typographic hierarchy and restrained grouping for forms. Make provider
rows easy to scan by grouping capabilities under the name and placing the
readiness status and drill-in affordance together. Keep the save footer pinned
and show status feedback when there is a pending change, a validation result,
or a repair context. In the focused window, the enabled save button uses a
white label on its accent background. Use the native label and background
for inactive and disabled states. Allow descriptions and form help to wrap at
the minimum size and with large accessibility text.

## Recording and recovery overlay

Keep routine feedback in a single-line capsule. Use system materials for the
capsule and recovery panel and the macOS accent for primary recovery actions.
Use a red recording indicator and a monospaced timer to make ongoing recording
easier to scan. Keep stop and cancel actions in their existing locations. Use
a distinct rounded panel for recovery with room for a multiline message and
labeled actions. Preserve the compact size targets, bottom-center placement,
non-activation, state messages, actions, accessibility announcements, and
session timing from the
[compact overlay specification](06-compact-transcription-overlay.md).

## Behavior

Preserve Settings destinations, transactional saves, focus and close
protection, provider configuration, and the macOS 15 deployment target.
Preserve dictation, recording, transcription, cleanup, and delivery behavior.
This specification supersedes the visual hierarchy and General section order
in the [modernized Settings specification](07-modernized-settings.md).

## Acceptance

General shows the selected pipeline at a glance. Settings controls remain
usable at the minimum window size, and provider details and save feedback
follow the same hierarchy as the destination pages. Recording remains compact,
and recovery copy and actions remain legible. Debug and Release builds pass.
