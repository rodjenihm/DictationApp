# Hold to dictate implementation plan

[Specification](../../../specifications/v1/features/16-hold-to-dictate.md)

1. Extend the global hotkey service to register two distinct chords,
   receive hold press and release events, and replace the active pair
   transactionally.
2. Track whether a hold started the current recording. Route release to
   the existing stop path, or cancel if microphone preparation is still
   in progress.
3. Add the hold binding to stored settings and the General pane. Reuse
   the native shortcut recorder and preserve the save and rollback flow.
4. Document both shortcuts in the README and the application
   specification. Verify the Debug and Release builds and check the
   affected runtime paths on macOS.

## Verification

- Signed arm64 Debug and Release builds passed with Xcode 27.2. Both app
  bundles passed strict code-signature verification. `git diff --check`
  passed.
- In an isolated macOS build, General showed both default bindings and an
  actionable warning when the running installation owned Option–Space.
  Verified native shortcut capture for both fields, duplicate rejection,
  the disabled hold state, and Escape during shortcut capture.
- Reviewed the recording state transitions for release during preparation,
  normal stop, cancellation, and late release. Live audio capture,
  provider delivery, and Settings persistence across relaunch remain
  unverified.
