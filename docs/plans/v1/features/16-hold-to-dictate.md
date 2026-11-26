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

## Fn shortcuts and Settings focus fix

- Signed Debug and Release builds passed with Xcode 27.2. Both app
  bundles passed strict code-signature verification.
- On macOS 27.0.1, started recording with the toggle shortcut recorder
  focused. Settings stayed responsive, disabled both recorders, and
  re-enabled them after Escape cancelled recording. The unified log
  showed no AttributeGraph cycle errors during the transition.
- Configured Fn–Space for toggle and Fn for hold through Settings and
  confirmed both saved bindings after quitting and relaunching. Verified
  that the installed app had an enabled session event tap for key-down,
  key-up, and modifier events.
- With synthesized keyboard events, verified Fn release stopped a hold,
  two Fn–Space presses toggled recording, and pressing Space during a
  standalone Fn hold kept recording after Fn release. Physical Fn key
  behavior was outside this verification.

## Fn defaults

- Signed Debug and Release builds passed. Launched the installed Release
  build with temporary shortcut preference overrides that exercised both
  defaults. Settings showed Fn–Space for toggle and Fn for hold, with no
  toggle reset action. Relaunched normally with the saved preferences.
- The permission grant transition was reviewed in code and was outside the
  manual verification.
