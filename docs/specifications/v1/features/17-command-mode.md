# Command Mode

Use a spoken instruction to replace selected text in a focused editable
field. For example, select a paragraph, hold Fn–Control, say “Translate this
to Spanish,” and release to apply the rewrite.

## Shortcut and capture

- Use Fn–Control as the default hold shortcut. Make it configurable and
  optional in **Settings → General**, alongside the dictation shortcuts.
  Offer Command–Control–Option as an alternative for keyboards without Fn.
- Match the chord regardless of which modifier is pressed first. Releasing
  either key ends the hold. Give the full chord precedence over standalone
  Fn dictation and prevent a late release from affecting another session.
- Before starting the microphone, require Accessibility permission and a
  readable, nonempty selection in a writable, non-secure control. If that
  cannot be verified, show a brief explanation and skip recording and
  provider calls. Support editors that expose sufficient selection
  information through macOS Accessibility.
- Allow only one active dictation or command session. Release before capture
  starts cancels the command. Escape cancels an active command. If recording
  ends unexpectedly or reaches its duration limit, discard the incomplete
  instruction.
- Use the non-activating overlay to distinguish listening for an instruction
  from applying it.

## Rewrite and replacement

- Use the selected transcription provider for the audio. Send the spoken
  command as an editing instruction and the selected text as document
  input to the configured cleanup provider. Carry out each requested edit,
  including additions after translation. The replacement contains the
  edited document text. The transcription language governs recognition of
  the instruction.
- Command Mode uses the configured cleanup model even when automatic
  dictation cleanup is off. Surface the provider and its processing
  location in Settings. A provider failure ends the command without
  replacing the selection or switching providers.
- Revalidate that the same app, window, control, selection range, and text
  are still focused immediately before replacing the selection. Paste the
  plain-text result without dictation-specific spacing. Preserve the
  clipboard through the existing ownership-checked transaction.
- Skip insertion for an identical result. If the target changed or delivery
  could not be confirmed, offer **Copy Result** without automatically
  leaving the result on the clipboard. Keep the result in memory only
  while the action is available.
- Keep selected text, speech, prompts, model output, and clipboard contents
  out of logs and persisted history.
