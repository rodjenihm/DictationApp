# Live Apple On-Device Transcription

**Status** · Implemented. In-app verification pending.

Reduce Stop-to-transcript latency on macOS 26 and later by running Apple
Speech analysis during recording when Apple On-Device is the selected
transcription provider and an explicit language is configured. The app uses
the same transcriber preset as for completed files. It displays and inserts
text only after Stop and successful M4A finalization.

## Capture and analysis

- Preserve the selected input, capture-start readiness, and M4A recording
  profile. Keep capture and speech analysis inactive between sessions.
- Start analysis concurrently with capture. Capture must not wait for speech
  asset lookup, model preparation, audio conversion, or a speech result.
- Send native mono PCM to the analyzer through a preallocated buffer that
  holds at most two seconds of input, capped at 384,000 frames. The audio
  callback copies samples only after the M4A writer accepts them. It does
  not allocate or wait on the analyzer for each buffer.
- Choose an audio format supported by the installed Speech modules. Convert
  PCM in batches of up to 50 milliseconds on the analyzer's input path and
  flush the converter at end of input. Feed no samples from outside the
  active recording.
- Finalize live analysis after input stops and all captured PCM is consumed.
  Accept only a nonempty final transcript from a fully drained, uninterrupted
  live input. If the live path is unavailable, its buffer overflows, it fails,
  or it has not finished within 250 milliseconds after a valid artifact is
  ready for transcription, use the existing completed-file path.

## Recovery and privacy

- Keep the completed M4A as the source for fallback, retry, and repair.
  The [Apple On-Device transcription specification](03-apple-on-device-transcription.md#transcription-runtime)
  defines the completed-file path.
  Preserve the minimum recording duration and all existing artifact lifetime
  rules. An unexpected capture failure continues to require a user's explicit
  action to transcribe the retained partial file.
- Stop live processing on cancellation and discard its results. A late result
  has no authority to publish text, modify the clipboard, or affect another
  dictation. No cloud provider receives live audio.
- Keep live samples and results local. The feature does not download assets
  while recording or change the optional post-processing configuration.
  Record only privacy-safe timing and outcome metadata.

## Acceptance

Live analysis runs during an ordinary eligible recording without delaying
microphone readiness. Compare first-buffer timing, Stop-to-final transcript,
and transcript quality against completed-file analysis on the same input and
locale. Cover cold and repeated starts, a short phrase, and longer speech.
Confirm that live failure returns to file analysis, retained partials require
consent, and cancellation leaves no late delivery.

[Apple SpeechAnalyzer documentation](https://developer.apple.com/documentation/speech/speechanalyzer)
