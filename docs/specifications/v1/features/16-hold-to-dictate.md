# Hold to dictate

Provide two configurable global shortcuts in **Settings → General**.

| Action | Default | Behavior |
| --- | --- | --- |
| Toggle dictation | Option–Space | Press to start. Press again to stop and transcribe. |
| Hold to dictate | Control–Shift–Space | Press the chord to start. Release the trigger key to stop and transcribe. |

Each shortcut uses a non-modifier key with at least one of Command, Option,
Control, or Shift. Assign distinct chords. Hold to dictate can be disabled.
Keep the existing saved toggle chord on upgrade. Use the hold default when
no hold preference exists, unless the toggle already uses that chord.

A hold starts a session only when the app would accept a new toggle
session. Releasing the hold stops only the session started by that press.
If release arrives before capture is ready, cancel startup without
transcribing. Additional presses during a session do not start another
session. Press the toggle shortcut or select **Stop** to finish an active
recording. Press Escape or select **Cancel** to discard an active session.
The resulting audio uses the same minimum duration, transcription, optional
cleanup, and text delivery paths as toggle dictation.

Apply shortcut edits with **Save Changes**. Reject duplicate bindings and
report macOS or application conflicts. A failed registration leaves the
previous active bindings in place. If startup cannot register a binding,
report the problem in Settings. Let the user use and configure the other
binding independently. Use the existing macOS hotkey registration mechanism
and permission model.
