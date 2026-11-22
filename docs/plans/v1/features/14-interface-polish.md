# Dictation interface polish implementation plan

[Specification](../../../specifications/v1/features/14-interface-polish.md)

## Implementation

1. Update the Settings sidebar, page and provider headers, form hierarchy,
   and save footer around the existing bindings and navigation.
2. Add the General pipeline summary and group everyday controls ahead of
   permissions when microphone access is available.
3. Refine the compact recording pill and recovery panel within the existing
   overlay rendering and state model.
4. Use neutral surfaces for Settings and system materials for the overlay.
   Keep the macOS accent for interactive selection and controls. Use an
   explicit white title on the enabled save button's accent bezel.
5. Build Debug and Release. Inspect the Settings layout in both appearances
   and the compact and recovery overlays, and record the evidence here.

## Verification evidence

- Unsigned arm64 Debug and Release builds passed with Xcode 27.2. The
  deployment target remains macOS 15. `git diff --check` passed.
- Isolated AppKit renders used the production Settings views with sample
  settings in light and dark appearances. The 880 by 660 point General
  render showed the microphone, provider, and cleanup summary and the
  aligned shortcut control. At 720 by 540 points, permission actions
  moved below the status when necessary, and the Luna Fast pricing and
  upload notes wrapped in the cleanup panel.
- The scratch renderer drew the native sidebar selection incorrectly in
  both the base and updated revisions. The shared preview shows the
  detail pane. Provider detail rendering confirmed the shared header and
  configuration layout.
- Synthetic overlay states rendered a 189 by 37 point recording pill
  and a 520 by 135 point recovery panel. The recovery message wrapped
  above the Settings, Retry, and Discard buttons.
- After palette feedback, Debug and Release builds passed again. Light and
  dark General renders confirmed neutral gray surfaces and emblems.
- Debug and Release builds passed after the save contrast fix. Isolated
  AppKit inspection in both appearances confirmed an enabled active button
  uses a white title and the accent bezel. Inactive and disabled states
  used the native title and bezel. The default button cell and Return key
  equivalent remained installed. The active accent bezel was verified by
  inspecting its property because the hidden window renders a neutral bezel.
