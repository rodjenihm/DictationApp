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
   runtime and Settings validation. Request Fast mode for GPT-6 Luna and
   retry in Standard when OpenAI identifies the tier as disallowed.
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
- Live provider calls and transcript latency were not measured.
