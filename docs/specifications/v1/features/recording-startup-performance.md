# Recording Startup Performance

**Status:** Complete

## Summary

Reduce the latency between an accepted dictation shortcut and the first audio
sample owned by DictationApp. The recording overlay must remain truthful: it
may acknowledge activation immediately, but it must not claim that recording
has started until the capture pipeline owns audio.

This specification refines the recording, sound-cue, cancellation, and
temporary-artifact requirements in
`docs/specifications/v1/application.md`. It preserves the provider and retained
recording behavior defined by the existing v1 specifications.

## Motivation

Before this change, the recorder constructed and started an
`AVCaptureSession`, waited for the full system start sound, started
`AVCaptureAudioFileOutput`, and waited for its delegate before entering the
recording state. Observed fresh-session latency was approximately 1.65 seconds,
and an otherwise warm session still required approximately one second. The
fixed start-sound and file-output confirmation costs dominated short
dictations.

Comparable dictation software initializes reusable processing components ahead
of the session, acquires the microphone into a streaming graph, and does not
serialize capture behind the entire feedback sound. DictationApp should adopt
the same latency-oriented shape without falsely reporting microphone readiness
or keeping the microphone active while idle.

## Goals

- Make ordinary warm recording startup feel immediate.
- Target the first owned audio buffer within 200 milliseconds of an accepted
  warm start on the built-in microphone under normal system load, with no more
  than 150 milliseconds spent between engine activation and that buffer.
- Keep startup device-dependent and report measured latency rather than
  promising a hard real-time bound.
- Preserve M4A/AAC/mono/16 kHz output and the existing `AudioArtifact`
  contract.
- Keep the microphone and its macOS privacy indicator inactive while the app
  is idle.
- Resolve the current default microphone for every session.
- Preserve cancellation, unexpected-capture recovery, duration limits,
  transcription, and artifact deletion semantics.
- Remove sound playback from the transcription critical path.

## Non-goals

- Guarantee zero-millisecond startup.
- Guarantee a fixed latency for Bluetooth, sleeping, disconnected, or
  reconfiguring audio devices.
- Keep a live microphone stream between dictation sessions.
- Show a recording state before DictationApp owns an audio buffer.
- Add live transcription, partial transcript presentation, or provider audio
  streaming.
- Change provider models, prompts, retry behavior, minimum recording duration,
  or the ten-minute maximum.
- Add a microphone picker or user-configurable recording format.
- Add an automated test target.

## Required behavior

### Reusable streaming capture

- Replace per-session `AVCaptureSession` and `AVCaptureAudioFileOutput`
  recording with a reusable in-process audio engine and per-session streaming
  writer.
- Construct reusable, non-capturing audio components before the first session
  where practical.
- Start the microphone only after the user explicitly starts dictation.
- Stop the microphone before publishing a finalized artifact, playing a stop
  cue, or returning to idle.
- Install a new per-session writer and output URL for every recording.
- Encode the captured stream incrementally as AAC in an M4A container using the
  active `RecordingProfile`.
- Resolve the default input and display name for each session. A macOS default
  device change while idle must apply to the next session.
- Enter the recording state only after the first audio buffer has been accepted
  by the session writer.

### Start feedback

- Replace the long system start sound with a bounded cue no longer than 120
  milliseconds.
- Prepare the capture graph and play the start cue concurrently.
- Do not wait for the start cue before accepting recording audio. Immediate
  first-syllable capture takes precedence over excluding the compact cue from
  recordings made through speakers.
- Starting a new session may interrupt unfinished feedback from an older
  session.
- If sounds are disabled, capture must not incur sound-related delay.

### Stop and cancellation feedback

- Stop and finalize capture before playing the stop cue.
- Start transcription as soon as the finalized artifact is ready; do not wait
  for the stop cue to finish.
- Cancellation must continue to return the coordinator to idle immediately and
  perform recorder teardown on the serialized capture boundary.
- A late cancellation cue must not delay or overlap the start cue for a
  replacement session.

### Failure and partial recovery

- Detect input-device disconnection, audio-engine configuration changes, writer
  failures, and unexpected engine termination.
- Attempt to finalize audio already accepted by the writer.
- Preserve the existing recoverable-partial rules: a valid artifact of at least
  500 milliseconds may be explicitly transcribed or discarded and must never
  be uploaded automatically.
- Delete invalid, empty, cancelled, stale, and duplicate artifacts.
- A failed start before the first accepted buffer must be reported as capture
  failure and must not transition through recording.

### Presentation

- Accept the shortcut and publish preparation immediately.
- Use concise activation copy if preparation remains visible long enough to be
  perceived.
- Transition to recording only after the first accepted audio buffer.
- Preserve the non-activating overlay, current input display, elapsed timer,
  Stop, Cancel, duration warning, and automatic stop behavior.

### Diagnostics

- Log privacy-safe monotonic durations for capture preparation, engine start to
  first buffer, total accepted-start to recording, and finalization.
- Never log audio buffers, transcripts, device identifiers, output paths, or
  provider payloads.
- Use the measurements to distinguish ordinary startup from device or system
  outliers.

## Performance acceptance

The implementation is accepted when:

- Warm built-in-microphone sessions normally reach their first accepted audio
  buffer within 200 milliseconds of the accepted start.
- Engine activation normally reaches its first accepted buffer within 150
  milliseconds.
- Preparation and cue playback overlap instead of adding their durations.
- Transcription begins without waiting for the stop cue.
- The app never presents recording before accepting the first buffer.
- A slower device remains cancellable and presents an honest activation state.

The timing values are normal-condition targets, not correctness boundaries.
Correct capture ownership, cancellation, privacy, and artifact integrity take
precedence when the operating system or device responds slowly.

## Privacy and security

- Pre-initialization must not activate the microphone or privacy indicator.
- Audio remains in the app-owned recording cache only for the existing session
  and retry lifetime.
- No new audio, transcript, credential, path, or device-identifier logging is
  permitted.
- Existing startup orphan cleanup and termination cleanup remain required.
