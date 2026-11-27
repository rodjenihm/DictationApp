# Command Mode implementation plan

[Specification](../../../specifications/v1/features/17-command-mode.md)

1. Add a persisted Command Mode shortcut and expose it in General Settings.
   Extend the existing hotkey registration and Fn event tap to track the
   command hold and arbitrate it against standalone Fn.
2. Capture the editable selection through Accessibility before opening the
   microphone. Keep its identity and range with the active command and
   revalidate immediately before dispatching the replacement.
3. Carry the command intent through the existing recording and transcription
   session. Route the completed instruction to the cleanup provider through
   an explicit text-edit request. Give the rewrite its own output rules and
   keep provider failures out of the dictation delivery fallback.
4. Connect command progress, cancellation, and result recovery to the
   existing overlay and configured provider Settings.
5. Build Debug and Release, check the diff, and record macOS verification
   and any runtime coverage gaps below.

## Verification

- Signed arm64 Debug and Release builds passed with Xcode 27.2. Both
  bundles passed strict code-signature verification. `git diff --check`
  passed.
- The Apple Intelligence provider translated a sample selection into
  Spanish on macOS 27.0.1 through the Command Mode request.
- In an isolated preferences domain, verified the default Fn–Control
  binding, persistence of Command–Control–Option, and persistence of the
  disabled state. The default dictation bindings remained Fn–Space and Fn.
- With an isolated pasteboard, verified shutdown restoration after the
  paste hold and preservation of a subsequent external clipboard write.
- The first installed Release build processed a physical Fn–Control
  command through Apple Speech and OpenAI. The user confirmed that
  the Spanish translation replaced the selection. Native undo remains
  unverified.

### Compound editing follow-up

The user reported a translation that included an instruction to append a
name. OpenAI now receives the spoken edit in its instructions and the
selection as document input. The instructions require every part of a
compound command to be applied to the replacement. Apple Intelligence
uses the two labeled fields in its prompt, which performed better in
local compound-edit runs.

- Verified the new OpenAI request layout with synthetic text. The
  selected text is the sole input field and the spoken command is in the
  instructions. The user then confirmed that the updated installed build
  translated an English selection into Spanish and appended a Spanish
  singer's name.
- The Apple Intelligence provider completed the translation and appended
  a Spanish singer for ordinary synthetic passages. It omitted the
  addition in one passage that itself contained an instruction.
- Debug build, signed Release archive, strict signature verification,
  and launch from `/Applications` passed.
