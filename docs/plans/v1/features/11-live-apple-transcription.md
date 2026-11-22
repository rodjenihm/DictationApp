# Live Apple On-Device Transcription Implementation Plan

**Status** · Implemented. In-app verification pending.

**Specification** · [Live Apple On-Device Transcription](../../../specifications/v1/features/11-live-apple-transcription.md)

## Implementation

1. Allocate the optional PCM ring after determining the input format. Use
   atomic producer and consumer cursors with release and acquire ordering.
   Close the input after AUHAL stops. Discard live analysis on overflow or
   cancellation and preserve normal asynchronous M4A writes.
2. Feed a pull-based async sequence to `SpeechAnalyzer`. Read input in
   bounded chunks. Use one `AVAudioConverter` where needed and drain it
   before terminating the sequence. Collect final segments with the same
   preset as completed-file analysis.
3. Start live analysis during capture only for the configured Apple
   transcription provider. After valid normal finalization, give an eligible
   result a short grace period before using the file. Keep retained-partial
   decisions, retries, and the existing delivery path on the coordinator.
4. Capture first-buffer, microphone stop, writer close, and artifact
   validation timing without logging from the audio callback. Build Debug
   and Release. Record any manual verification and measurements available
   on an eligible Mac with installed Apple Speech assets.

## Verification evidence

- November 22, 2026. Unsigned arm64 Debug and Release macOS builds passed
  with Xcode 27.2 and complete strict concurrency. Xcode reported local
  device-support and simulator warnings. Swift emitted no source diagnostics.
- The live source holds at most two seconds of native mono PCM, capped at
  384,000 frames. The analyzer pulls up to 50 milliseconds at a time. The
  coordinator waits up to 250 milliseconds for a final live result once it
  has a valid artifact for transcription.
- November 22, 2026. On macOS 27.0.1, local synthesized speech fed through
  the production PCM ring and converter yielded 80,132 frames at 16 kHz
  from 240,396 frames at 48 kHz. The sequence confirmed a fully drained end
  of input. The same probe confirmed that overflowing the ring invalidates
  live input. It used a temporary file and did not activate the microphone.
- The command-line Speech probe found the on-device transcriber available.
  The locale assets reported `.supported` from the probe process and failed
  the provider's installed-asset requirement. No asset reservations or
  installations changed.
- A subsequent user-run Xcode session logged four live Apple transcription
  results, each followed by confirmed delivery. Transcript quality and
  comparative latency remain unverified.
