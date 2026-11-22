# OpenAI Model Migration

**Status** · Implemented

## Goal

Replace retiring OpenAI models with current equivalents. Preselect a fast
cleanup model for new configurations and keep cloud transcription on the
completed-file endpoint.

## Model catalog and saved selections

The OpenAI model pickers offer GPT-Transcribe for transcription and GPT-6
Luna and GPT-6.1 Terra for cleanup. GPT-Transcribe and GPT-6 Luna are the
defaults for new configurations. Migrate both legacy curated cleanup models
to GPT-6 Luna to prioritize latency for existing configurations. GPT-6.1
Terra remains available for users who prefer a more capable cleanup model.
Cleanup remains opt-in.

OpenAI plans to retire both previous cleanup models on December 11, 2026,
and both previous transcription models on February 26, 2027. When loading
saved settings, map these curated selections to their replacements.

| Stage | Previous curated model | Replacement |
| --- | --- | --- |
| Transcription | `gpt-4o-transcribe` or `gpt-4o-mini-transcribe` | `gpt-transcribe` |
| Cleanup | `gpt-5-mini` or `gpt-5-nano` | `gpt-6-luna` |

Migrate remembered OpenAI selections for inactive stages and providers as
well. Keep custom model IDs, enabled stages, provider and language
selections, and stored credentials. Loading applies the mapping in memory
and the next Settings save persists the current selections.

## Request behavior

- Upload the finalized M4A to `/v1/audio/transcriptions` and read `text`
  from the JSON response. GPT-Transcribe may return detected languages,
  which this app does not use.
- Use the default chunking behavior for GPT-Transcribe. Keep automatic
  chunking for the other file model IDs.
- Encode a selected language as one multipart `languages[]` field for
  GPT-Transcribe and as `language` for legacy and other custom file
  models. Omit the hint when language selection is Automatic. Settings
  validation uses the same file request fields and selected language.
- Send `reasoning.effort: none` for GPT-6 Luna and GPT-6.1 Terra in both
  Settings validation and runtime cleanup, including when either model ID
  is typed as a custom selection. Custom model IDs outside the curated
  catalog continue to use the existing `minimal` effort.
- Request `service_tier: fast` for GPT-6 Luna in runtime cleanup and Settings
  validation. Label the Luna option with Fast mode pricing. OpenAI bills Luna
  requests served in Fast mode at twice the applicable Standard token rate.
  Accept successful responses served at Standard rates when OpenAI
  downgrades the tier.
- If OpenAI explicitly rejects Fast mode for the project with HTTP 400 and
  identifies `service_tier` as the invalid parameter, try Standard. Apply
  the existing cleanup deadline and retry limit to the attempt. Preserve the
  project's tier selection for other models.
- Preserve the existing cleanup instructions, output validation, and raw
  fallback. OpenAI receives completed audio only after Stop and receives
  transcript text only when cloud cleanup is enabled.

See the [OpenAI deprecation schedule](https://developers.openai.com/api/docs/deprecations),
[file transcription guide](https://developers.openai.com/api/docs/guides/speech-to-text),
[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna),
[GPT-6.1 Terra](https://developers.openai.com/api/docs/models/gpt-6.1-terra),
[Fast mode](https://developers.openai.com/api/docs/guides/fast-mode), and
[API error codes](https://developers.openai.com/api/docs/guides/error-codes).
