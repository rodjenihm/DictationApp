# Hold to dictate

Provide two configurable global shortcuts in **Settings → General**.

| Action | Default | Behavior |
| --- | --- | --- |
| Toggle dictation | Fn–Space | Press to start. Press again to stop and transcribe. |
| Hold to dictate | Fn | Hold to start. Release Fn to stop and transcribe. |

Each shortcut accepts a non-modifier key with at least one of Command,
Option, Control, or Shift. Either shortcut also accepts Fn–Space, and hold
to dictate accepts Fn alone. Assign distinct bindings. Hold to dictate can
be disabled.
Use the defaults when no shortcut preference exists. Preserve saved
shortcuts and the disabled hold preference on upgrade.

A hold starts a session only when the app would accept a new toggle
session. Releasing the hold stops only the session started by that press.
If release arrives before capture is ready, cancel startup without
transcribing. Additional presses during a session do not start another
session. Press the toggle shortcut or select **Stop** to finish an active
recording. Press Escape or select **Cancel** to discard an active session.
The resulting audio uses the same minimum duration, transcription, optional
cleanup, and text delivery paths as toggle dictation.

Allow 150 ms before starting a standalone Fn hold so a chord can arrive
first. When Fn–Space toggles dictation and Space arrives after the hold
has started, the same recording continues as a toggle session. Releasing
Fn then leaves the recording active. Other Fn key combinations pass
through to macOS or the frontmost app.

Apply shortcut edits with **Save Changes**. Reject duplicate bindings and
report known macOS or application conflicts. A failed registration leaves
the previous active bindings in place. If startup cannot register a binding,
report the problem in Settings. Let the user use and configure the other
binding independently. Standard chords use macOS hotkey registration. Fn
bindings use a keyboard event tap and require Accessibility access. Activate
permission-blocked Fn bindings when the user grants access and returns to
the app.

Settings actions become read-only as soon as dictation starts. Apply the
native controls' enabled state after SwiftUI finishes updating the window
so AppKit can change keyboard focus without reentering the update.
