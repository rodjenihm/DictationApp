# Cleanup fallback feedback

When transcription succeeds and cleanup falls back to the original text,
show why in the existing overlay and menu-bar status. Use plain language
and describe the actual delivery outcome.

| Cleanup outcome | Overlay after confirmed paste |
| --- | --- |
| Cleanup provider could not complete the request | Cleanup couldn’t finish · Original text pasted |
| Cleanup reached its deadline | Cleanup took too long · Original text pasted |
| The app rejected a returned edit | Cleanup edit rejected · Original text pasted |

Treat Apple's spoken-wording check and the shared output checks as edit
rejections. A missing result or an error from a provider is a cleanup
failure. Retain available setup, language, or model guidance in the
menu-bar status. When Apple's wording check rejects an edit, explain in
the menu bar that cleanup changed the user's words.

Use the existing clipboard or unverified-insertion status when delivery
is uncertain. Include the cleanup reason and say when the original text
is available to paste from the clipboard. Announce the reason and outcome
to VoiceOver for confirmed raw-text delivery.

Keep the cleanup deadline, retries, provider checks, output acceptance
rules, paste behavior, and overlay duration. Log the wording rejection
using a fixed reason code. Exclude transcripts and model output from logs.
