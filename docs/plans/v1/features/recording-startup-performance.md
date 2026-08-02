# Recording Startup Performance Implementation Plan

**Status:** Complete

**Specification:** `docs/specifications/v1/features/recording-startup-performance.md`

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Capture and cue latency instrumentation | Complete | Added monotonic preparation, engine-to-buffer, total-start, and finalization timing | Old logs measured 1,648 ms fresh and 972 ms warm accepted-start latency; new live logs expose each capture interval |
| 2. Concurrent bounded start feedback | Complete | Start feedback is capped at 120 ms, interrupts stale cues, and no longer gates capture | Source inspection plus live startup measurements |
| 3. Reusable streaming M4A recorder | Complete | Replaced per-session capture sessions with reusable `AVAudioEngine` input and per-session asynchronous AAC/M4A writing | Complete-strict Debug build, live first-buffer capture, clean cancellation teardown, and isolated 16 kHz mono AAC/M4A probe at the encoder-supported 48 kbps rate |
| 4. Non-blocking stop feedback and integration | Complete | Stop feedback is enqueued after finalization without blocking duration validation or transcription; activation copy is truthful | Source inspection and Debug build |
| 5. Final build and manual verification | Complete | Verified cold/warm microphone startup and cancellation without issuing a provider request | Debug and Release builds succeeded; live measurements were 493 ms cold and 177 ms warm, with 157 ms and 110 ms engine-to-buffer latency respectively |

Update this table after every phase. A phase becomes Complete only after its
gate passes, and only one incomplete phase may be Next.

## Phase 1 — Capture and cue latency instrumentation

- Add privacy-safe monotonic timing around accepted start, capture preparation,
  first accepted buffer, and finalization.
- Preserve the current logging categories and never include paths, audio,
  transcripts, credentials, or device identifiers.
- Establish the old recorder's observed baseline from existing structured logs.

Gate: Debug build succeeds and logs expose each critical-path interval without
sensitive values.

## Phase 2 — Concurrent bounded start feedback

- Bound the recording-start cue to at most 150 milliseconds.
- Interrupt stale feedback when a new start cue begins.
- Run recorder preparation and start-cue playback concurrently.
- Start capture without awaiting the cue so first-syllable ownership is not
  delayed by feedback playback.
- Keep sound-disabled startup free of cue delay.

Gate: Debug build succeeds; source inspection confirms preparation and feedback
are concurrent and feedback does not gate recording.

## Phase 3 — Reusable streaming M4A recorder

- Replace `AVCaptureSession`/`AVCaptureAudioFileOutput` with one reusable
  `AVAudioEngine` and a per-session asynchronous extended-audio-file writer.
- Resolve the default device and native input format for every session.
- Convert and encode native input incrementally to the active AAC/M4A recording
  profile.
- Resume startup only after the first buffer is accepted.
- Preserve serialized engine ownership, cancellation, delegate-equivalent
  unexpected failure reporting, partial finalization, validation, and artifact
  deletion.
- Keep the narrow unchecked Sendable boundary documented where Core Audio and
  AVFoundation objects cross their serialized callback boundary.

Gate: Complete-strict Debug build succeeds, live input reaches the writer, and
an isolated writer probe produces a readable mono 16 kHz AAC M4A artifact.

## Phase 4 — Non-blocking stop feedback and integration

- Enqueue the stop cue only after local capture is finalized.
- Continue directly into duration validation and transcription without awaiting
  sound completion.
- Preserve too-short, automatic-limit, cancellation, retained-partial, and
  provider transitions.
- Update visible preparation copy to describe microphone activation accurately.

Gate: Complete-strict Debug build succeeds and source/log timing confirms no
stop-sound duration on the transcription critical path.

## Phase 5 — Final build and manual verification

- Build Debug and Release with the repository's persisted Complete strict
  concurrency settings.
- Exercise a fresh start, a repeated warm start, and cancellation without
  allowing a provider request.
- Record device-dependent startup intervals without treating the target as a
  hard guarantee.
- Verify output container, codec, channels, sample rate, duration, file size,
  supported encoder bitrate, and cleanup with an isolated local writer probe.
- Run `git diff --check` and repository artifact/privacy checks.

Gate: Debug and Release builds succeed, manual capture evidence is recorded,
and repository checks pass.

## Expected result

- Ordinary warm starts reach recording in approximately 100–200 milliseconds;
  the measured implementation reached the first accepted buffer in 177 ms.
- Cold and Bluetooth starts may take longer but remain truthful and cancellable.
- Finalized audio proceeds to transcription without the previous stop-cue wait.
- The microphone remains inactive while idle.

## Assumptions

- The M4A/AAC/mono/16 kHz recording profile remains required by both configured
  transcription providers.
- Reusable processing objects may remain allocated while idle, but the input
  device and audio engine must be stopped.
- Existing provider, clipboard, Accessibility, Settings, and retry behavior is
  unchanged.
- Build artifacts stay outside the repository.
- This file is the sole progress ledger for the feature.
- No commits or pushes are created.
