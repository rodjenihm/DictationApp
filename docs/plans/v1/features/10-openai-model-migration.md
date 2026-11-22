# OpenAI Model Migration Implementation Plan

**Status** · Complete

**Specification** · [OpenAI Model Migration](../../../specifications/v1/features/10-openai-model-migration.md)

## Implementation

1. Update the OpenAI model catalog and defaults. Map known saved curated
   selections as settings load, including selections for inactive stages.
   Use GPT-6 Luna for both legacy cleanup selections to prioritize speed.
2. Share the transcription request body between runtime and Settings
   validation. Encode GPT-Transcribe's language hint using its array field.
3. Use shared cleanup request fields for reasoning and processing tier in
   runtime and Settings validation. Persist Luna's Fast opt-in alongside
   cleanup settings, with Standard as the default for existing and new
   configurations. Snapshot the saved choice at session start. Retry in
   Standard when OpenAI identifies Fast as disallowed.
   Give the price note and upload disclosure separate, vertically expanding
   rows aligned with the model picker.
4. Verify Debug and Release builds and check the working diff for
   whitespace errors. Review request fields against the published API
   contract without sending audio or transcripts.

## Verification evidence

- November 22, 2026 · Unsigned macOS arm64 Debug and Release builds passed
  with Xcode 27.2. `git diff --check` passed.
- Confirmed the file model, JSON response, multipart `languages[]` field,
  model retirement dates, and cleanup reasoning settings against the
  provider documentation linked in the specification.
- Confirmed the Luna Fast tier, its pricing, and the documented tier-denial
  response against the same provider documentation. Both cleanup requests
  use the shared payload. Runtime fallback consumes an existing retry
  attempt and respects the cleanup deadline.
- A user-run session on the preceding build recorded three successful
  cleanup requests and one cleanup deadline fallback. The app's logs did
  not identify the service tier OpenAI used.
- Unsigned Debug and Release builds passed for the opt-in follow-up.
  A local check with the production encoder confirmed that saved
  configurations without the preference decoded as Standard.
  Opt-in survived encoding, decoding, and the session snapshot and repair
  paths. Luna encoded `default` with the preference off and `fast` with it
  on. Terra omitted the tier. The follow-up made no live API requests.
- The spacing follow-up passed unsigned Debug and Release builds. Isolated
  SwiftUI renders at 525 and 350 points and in the accessibility layout
  showed separate rows and full wrapping for the price and upload text.
