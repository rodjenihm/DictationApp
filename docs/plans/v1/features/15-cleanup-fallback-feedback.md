# Cleanup fallback feedback implementation plan

[Specification](../../../specifications/v1/features/15-cleanup-fallback-feedback.md)

1. Classify Apple's wording rejection as an output-policy error. Use the
   existing rejection log path with a fixed reason code.
2. Carry the cleanup reason through delivery. Use the classified message
   in the compact pill, menu-bar status, and VoiceOver announcement. Keep
   the delivery instructions on existing clipboard and unverified states.
3. Build Debug and Release. Inspect the rendered fallback messages and
   record verification evidence.

## Verification evidence

- Unsigned arm64 Debug and Release builds passed with Xcode 27.2.
  `git diff --check` passed.
- Replaying the short on-device example in an isolated process produced
  `wording_changed` and the explanation that cleanup changed the user's
  words.
- Offscreen AppKit renders of all three production overlay messages fit
  on one line in light and dark appearances. Their widths ranged from
  288 to 298 points at standard text size.
- Source review confirmed that the pasted label is used only for
  confirmed delivery. The clipboard and unverified messages keep the
  cleanup reason and the appropriate delivery instructions.
