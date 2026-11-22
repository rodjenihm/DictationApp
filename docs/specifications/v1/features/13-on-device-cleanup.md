# On-Device Transcript Cleanup

## Purpose

Offer an optional cleanup provider that edits the raw transcript on the Mac.
Cleanup improves punctuation and paragraph breaks and removes clear fillers
and accidental word repetitions. It preserves meaning, names, numbers,
technical terms, and the original language.

## Settings

- Add **Apple Intelligence** as a cleanup provider, with a single system
  model. Its availability is independent of Apple On-Device transcription,
  Speech Recognition permission, and Speech language assets.
- Offer the provider on macOS 26 and later. Show why it is unavailable in
  Providers when macOS or the system model is not ready, and let users
  select it for cleanup once it is ready.
- Keep cleanup disabled by default. Preserve existing provider, model, and
  Fast mode selections. Apply a provider change after **Save Changes**.
- Identify Apple Intelligence cleanup as on-device. The transcription
  provider remains independently selectable. This cleanup requires no API
  key. Validate the selected Apple provider and its model availability
  locally during Settings save.

## Processing and fallback

- Use Apple's on-device `SystemLanguageModel` and a fresh session for each
  dictation. Use the raw text as editing input. Treat instructions spoken
  in the transcript as text. Use no model tools.
- Keep local edits conservative. Allow punctuation, capitalization,
  paragraph breaks, adjacent word repetitions, and clear English fillers.
  Preserve spoken corrections as written. Reject inserted or substituted
  words and other word removals, independently of the model instructions.
  Preserve numeric literals and punctuation within technical terms,
  including identifiers and signed numbers.
- Remove one matching pair of presentation quotes around the entire model
  response when the raw transcript has no quotes at its boundaries. Decode
  a complete JSON string before taking its contents so embedded quotes and
  line breaks are interpreted correctly. Apply the same wording and output
  checks to the unwrapped text. Preserve quotations that are part of the
  original dictation.
- For an explicit transcription language, check model locale support
  before generation. For Automatic, let the system model handle the
  language of the input. Preserve mixed language text.
- Apply the shared cleanup deadline and output checks. If the system model
  is unavailable, the language or transcript length is unsupported,
  generation fails, output is invalid, or the deadline expires, deliver
  the raw transcript. An unavailable model may recover on the next
  session. Cancellation and session replacement prevent late delivery.
- Route the transcript only to the cleanup provider selected when dictation
  starts. Apple Intelligence cleanup uses no cloud fallback. Keep audio
  and transcript storage and disposal under the application specification.
- Keep model inputs, outputs, session history, and framework error text out
  of application logs. Record only privacy-safe outcomes, output rejection
  categories, and timing.

## Acceptance

Apple Intelligence can be selected independently of the transcription
provider on an eligible Mac. A successful local edit goes through the
existing insertion path. Unsupported input and unavailable local editing
produce a single raw delivery. Existing configurations and macOS 15 builds
continue to work.

[Apple's on-device model documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
· [Language and locale support](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
