# On-Device Transcript Cleanup Implementation Plan

**Specification** · [On-Device Transcript Cleanup](../../../specifications/v1/features/13-on-device-cleanup.md)

**Status** · Implemented, live cleanup and paste verified

## Implementation

1. Check the availability and editing behavior of the host's on-device
   system model with synthetic text. Leave system assets and user settings
   untouched.
2. Add a cleanup-only Apple Intelligence registration. Reuse the existing
   provider picker, settings validation, per-session configuration, cleanup
   deadline, and raw fallback. Keep the single system model implicit in
   Settings.
3. Use one local generation per transcript. Preserve cancellation, gate
   explicit locales, and map local failures to short actionable messages.
   Restore the normal raw delivery path on local model failures.
   Remove one surrounding quote wrapper from otherwise eligible local
   output and record the reason when shared validation rejects an edit.
4. Update the README and application specification to describe the separate
   transcription and cleanup choices. Build Debug and Release, check
   availability guarding and request routing, and record verification
   evidence here.

## Verification evidence

- Unsigned macOS arm64 Debug and Release builds passed with Xcode 27.2.
  Swift emitted no application source diagnostics. The app weak-links
  Foundation Models and guards the provider with macOS 26 availability.
- The host on macOS 27.0.1 reported an available on-device model. An initial
  synthetic probe showed that unrestricted cleanup could change the meaning
  of a spoken correction. The implementation checks wording, numbers, and
  technical literals before accepting an edit.
- A follow-up synthetic probe called the production provider and shared
  output validation. Three short English samples produced accepted edits
  in 1.95, 0.55, and 0.50 seconds. An explicit unsupported locale returned
  raw fallback before generation.
- The probe used synthetic text, without opening the microphone or
  clipboard, installing models, or sending provider requests.
- A user-run Apple Intelligence dictation fell back to the raw transcript
  after 2.117 seconds, with confirmed delivery. Replaying the input through
  the provider reproduced a full quotation wrapper over otherwise valid
  text. This triggered the shared output check.
- After the fix, the same input passed in explicit English and Automatic
  modes. The model kept the wording unchanged in those replays. A local
  check confirmed correct decoding of embedded quotes and a line break
  and preserved original boundary quotes.
- An identical-input comparison used a synthetic handoff with technical
  identifiers, a negation, and two spoken corrections. With the app's
  cleanup deadline, Apple Intelligence fell back after 5.21 seconds and
  Luna Fast completed in 1.86 seconds. A local Apple rerun finished in
  4.38 seconds and passed validation, but its punctuation made a date
  correction read backwards. Luna kept the intended date clear and
  resolved the corrected request count. This comparison excludes speech
  recognition and paste.
- After the quote-wrapper fix, a user-run Apple Intelligence dictation
  completed cleanup in 2.675 seconds. The app dispatched the paste 3.404
  seconds after Stop and confirmed delivery.
- Quality and latency across representative dictations remain unverified.
