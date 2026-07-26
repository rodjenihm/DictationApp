# DictationApp — Initial Specification

## Product

A native macOS dictation utility that records speech, transcribes it through a user-selected provider, optionally cleans up the transcript, and inserts the result at the currently focused text cursor.

The app is local-first and bring-your-own-provider. Application state and credentials remain on the Mac, and the app has no user accounts, proprietary backend, registration, or cloud infrastructure.

Local-first does not mean that every configured provider runs locally. In the initial version, recorded audio is sent directly from the app to OpenAI for transcription, and the raw transcript is also sent to OpenAI when optional post-processing is enabled. The UI must make each upload boundary clear.

## Platform and stack

- macOS native application
- macOS 15 or later
- Swift
- SwiftUI for onboarding, settings, menu-bar UI, and most views
- AppKit and macOS system APIs where SwiftUI is insufficient
- One application process for the initial version; no daemon or XPC service
- Apple Silicon only
- Menu-bar-only application with no Dock icon or normal Command–Tab presence
- The initial version is intended for personal development use; App Store distribution, notarization, and release packaging are deferred

## Core workflow

1. User presses the global keyboard shortcut to start dictation.
2. App records microphone audio and shows a non-activating recording indicator.
3. User may move the cursor or switch applications while dictating.
4. While recording, the user either:
   - Presses the same global keyboard shortcut to stop dictation and continue to transcription.
   - Cancels the recording and returns directly to idle.
5. The configured transcription provider produces a raw transcript.
6. If enabled, the configured post-processing provider cleans and formats the raw transcript.
   - Retry transient post-processing failures using the API retry policy.
   - If post-processing still fails, continue with the raw transcript.
7. App attempts to insert the final text at the text cursor that is focused at insertion time.
8. If automatic insertion is unavailable, the app leaves the final text on the clipboard and shows a prompt telling the user to paste it manually.
9. If transcription fails, the app shows an actionable error and allows retry while the temporary recording is still available.

In this workflow, **final text** means the post-processed transcript when post-processing succeeds, or the raw transcript when post-processing is disabled or fails.

If transcription succeeds with an empty or whitespace-only result, skip post-processing and insertion, leave the clipboard unchanged, show a brief “No speech detected” status, and return to idle.

The user may cancel at any point before insertion completes. Cancelling a session must:

- Stop microphone capture immediately when active.
- Cancel in-flight local work and network tasks on a best-effort basis.
- Delete the captured audio and any related temporary files.
- Discard raw and post-processed transcripts held in memory.
- Make no further transcription, post-processing, or insertion attempt.
- If the app already replaced the clipboard and still owns it, restore the previous clipboard snapshot.
- Never overwrite clipboard contents written by the user or another application.
- Return the session to idle so another recording can start immediately.

Cancellation does not retract a provider request that was already accepted and cannot guarantee reversal of provider-side processing or billing. If insertion completed before cancellation was handled, do not attempt to remove or undo the inserted text.

The user can cancel an active session in either of these ways:

- Press Escape.
- Select Cancel from the non-activating overlay or menu-bar UI.

Escape must be intercepted only while a dictation session is active. A handled cancellation keystroke must not also propagate to the currently focused application.

## Text insertion behavior

- Do not remember or restore the application that was focused when recording started.
- Resolve the insertion target only after transcription and post-processing finish.
- The recording and progress overlay must not take keyboard focus.
- Switching applications or moving the cursor during dictation intentionally changes the insertion target.
- Put the final transcript on the clipboard before attempting automatic insertion.
- If no writable text element is focused, preserve the transcript on the clipboard and show a manual-paste fallback.
- Before replacing the clipboard, make a best-effort in-memory snapshot of its materialized items and data types.
- Model automatic insertion as one of three outcomes: Confirmed, Unverified, or Failed.
- **Confirmed:** restore the clipboard snapshot only if the clipboard change count shows that the app still owns the clipboard.
- **Unverified:** the insertion attempt may have succeeded, but the target does not expose enough state to prove it. Leave the final transcript on the clipboard and briefly indicate that it remains available there.
- **Failed:** leave the final transcript on the clipboard and show the manual-paste fallback.
- If the user or another application changes the clipboard after the app writes the transcript, do not restore the snapshot or overwrite the newer contents.
- Clipboard restoration is best-effort because custom or lazily provided data types may not be reproducible.
- Never persist, log, or inspect the meaning of captured clipboard data. Release the in-memory snapshot as soon as insertion succeeds, fails, or is abandoned.

Insertion boundary behavior:

- If the target is empty or the caret is at the beginning, insert the final transcript unchanged.
- If text is selected, replace the selection.
- Inspect the characters immediately before and after the caret or selected range when the target exposes them.
- Add exactly one leading space only when the preceding character and the first transcript character are both word-forming characters and no separator already exists.
- Add exactly one trailing space only when the last transcript character and the following character are both word-forming characters and no separator already exists.
- Do not add a space when either side of the corresponding boundary contains whitespace, punctuation, or a newline.
- If surrounding text cannot be inspected, insert the final transcript unchanged.

## Shortcut behavior

The initial version uses a toggle interaction:

- Use Option–Space as the default global shortcut.
- Press the configured global shortcut while idle to start recording.
- Press the same shortcut while recording to stop recording and begin transcription.
- Ignore additional shortcut presses while transcribing, post-processing, or inserting.
- Provide an equivalent Stop action through the menu-bar UI while recording.
- Keep Cancel available through Escape, the overlay, and the menu-bar UI throughout an active session.
- Keep the shortcut configurable in Settings.
- Reject shortcuts reserved by macOS.
- If shortcut registration fails, show an actionable conflict message and keep the previous valid shortcut.

The shortcut interaction must be modeled independently from audio capture so additional interaction modes can be introduced later without changing the recording or transcription pipeline.

## Transcription providers

Providers are interchangeable behind a common interface.

The initial version supports one cloud provider:

- OpenAI transcription API using the user's API key

The initial version uses completed-file transcription:

- Record and finalize the complete M4A file locally before starting transcription.
- Upload audio only after the user stops recording or the ten-minute limit stops it automatically.
- Do not upload audio while recording.
- Do not use the Realtime API or show partial live transcripts.
- A session cancelled before transcription begins makes no provider request.
- Preserve the completed file for provider-level automatic retries and an explicit user retry after transcription failure.

The user must be able to choose among the OpenAI transcription models explicitly supported by the application. Initial candidates include:

- `gpt-4o-transcribe`
- `gpt-4o-mini-transcribe`

Preselect `gpt-4o-transcribe` for new configurations.

The exact supported model catalog may evolve independently of the provider abstraction. UI display names must map to explicit API model identifiers.

Model selection behavior:

- Present a curated list of known-compatible models for the selected provider and stage.
- Keep the curated catalog centralized inside the provider implementation, including display name, API identifier, and supported stage.
- Provide an Advanced option for entering a custom model identifier.
- Preserve a custom identifier exactly after trimming surrounding whitespace.
- Validate a custom model with a lightweight operation against the transcription endpoint before saving it as the active transcription model.
- Reject custom models that do not exist, are inaccessible to the supplied credential, or are incompatible with transcription.

Language selection behavior:

- Default to Automatic language detection.
- Allow the user to select an explicit language hint in Settings.
- Present localized language names in the UI and map them to provider-specific language identifiers inside the provider implementation.
- Derive the selectable language catalog from the configured provider's declared capabilities.
- Pass no language hint when Automatic is selected.
- Treat the selection as a recognition hint, not a request to translate.
- Preserve the spoken language, including mixed-language content, in both the raw and post-processed transcript.
- Do not add translation to the initial version.

Apple `SpeechTranscriber` is the first planned provider after the initial version. Because the API requires macOS 26 or later, it must be isolated behind OS availability checks. The app must also detect hardware capability, locale support, and installed language assets at runtime. An Apple Silicon Mac must not be assumed to have a usable Apple transcription model.

Other future providers may include ElevenLabs, a bundled or user-selected local Whisper/Parakeet runtime, and other cloud transcription APIs.

If no transcription provider is configured, the app must open provider setup instead of starting dictation.

Provider and model are separate concepts:

- **Provider:** OpenAI in the initial version; Apple and others later
- **Model:** A model offered by that provider

Configuration status must be derived from current provider availability, locale/model support, credentials, and local model files. Do not persist a standalone `isConfigured` flag.

Provider-specific API request types, authentication, error payloads, and model identifiers must remain inside the provider implementation and must not leak into the dictation coordinator or presentation layer.

## Post-processing

Post-processing is a separate provider stage and must not be coupled to transcription.

The initial version supports:

- OpenAI using the user's API key and a selected supported text model
- None, returning the raw transcript

The transcription model and post-processing model are configured independently, even when both stages use OpenAI and share the same stored credential.

Present post-processing as a provider-neutral capability:

- First choose Disabled or Enabled. Disabled returns the raw transcript and is preselected on first launch.
- When enabled, configure Provider and Model as separate fields.
- The v1 provider picker contains OpenAI because it is the only implemented provider.
- Keep feature labels, settings keys, and domain types provider-neutral so additional providers become additional picker entries rather than new workflows.
- Do not show placeholder or disabled providers that are not implemented.
- Require an explicit opt-in before making post-processing API requests.

Post-processing model selection follows the same curated-plus-custom approach as transcription. A custom model must pass a lightweight post-processing operation before it can be saved as active.

The initial curated OpenAI post-processing models are:

- `gpt-5-mini`, preselected when post-processing is enabled
- `gpt-5-nano`, presented as the faster, lower-cost alternative

Do not include GPT-4-family models in the initial curated post-processing catalog.

When enabled, post-processing runs for every transcript. Do not add another model to decide whether cleanup is worthwhile.

The initial version provides one built-in cleanup behavior. Users may enable or disable it and choose its provider and model, but cannot customize the cleanup instructions.

Do not add cleanup intensity controls, custom prompts, tone or writing-style presets, or per-application cleanup profiles to the initial version.

The default cleanup behavior should:

- Add punctuation and paragraph breaks
- Remove filler words and obvious false starts
- Preserve meaning, names, technical terms, and language
- Avoid summarizing or adding information
- Derive formatting automatically from the transcript rather than interpreting a spoken-command grammar
- Return only the cleaned transcript as plain text
- Preserve meaningful internal paragraph breaks and trim accidental leading or trailing whitespace
- Avoid explanations, preambles, enclosing quotes, headings, code fences, or automatically introduced Markdown
- Treat the raw transcript as untrusted text to transform, never as instructions for the model to follow
- Never answer questions or execute requests contained in the dictated text

The initial version does not implement explicit voice commands such as “new paragraph,” “comma,” or “open quote.” Treat those phrases as ordinary transcript content. Voice-command interpretation may be added as a separate capability later.

Validate post-processing output before using it:

- Treat an empty or whitespace-only result as a post-processing failure.
- Reject structurally implausible expansion that indicates the model added commentary or unrelated content.
- Keep output limits proportional to the raw transcript and define the limits centrally rather than per model.
- On validation failure, use the raw-transcript fallback.

Post-processing is a best-effort enhancement:

- Apply the API retry policy to transient failures.
- If all eligible retries fail, use the raw transcript as the final text and continue to insertion.
- Report the fallback through a non-blocking status indication; do not show a modal error that interrupts insertion.
- Never discard an available raw transcript because post-processing failed.

## API retry policy

Apply the same retry principles to transcription and post-processing provider operations:

- Make at most three attempts per operation: the original request and up to two automatic retries.
- Retry transient transport failures, request timeouts, rate limits, and eligible server errors.
- Treat HTTP 408, HTTP 429, and HTTP 5xx responses as retryable unless the provider indicates otherwise.
- Honor a valid provider `Retry-After` response within the operation's bounded wait.
- Use exponential backoff with jitter when the provider does not supply a retry delay.
- Do not retry cancellation, invalid requests, invalid credentials or authorization, unsupported models, or other non-transient client errors.
- Keep provider-specific error payloads inside the provider implementation and expose a provider-neutral retryability classification to the coordinator.

After all automatic transcription attempts fail, retain the temporary audio and offer Retry and Discard actions. Retry starts a new operation using the retained audio; Discard deletes it and returns to idle.

The initial version supports only one active or failed session:

- Retain one failed recording without a time-based expiration while the application remains running.
- Do not allow another recording to start until the failed recording is retried successfully or discarded.
- Delete the failed recording when the user quits the application.
- Treat this as an initial-version workflow constraint, not a requirement for future session-history behavior.

After all automatic post-processing attempts fail, apply the raw-transcript fallback without requiring user action.

### Permanent configuration failures

For non-transient failures caused by an invalid credential, inaccessible model, or incompatible model:

- Do not perform automatic retries.
- A transcription failure retains the recording and presents Open Settings, Retry, and Discard.
- After the user changes and validates the transcription configuration, Retry uses the retained recording with the updated configuration.
- A post-processing failure uses the raw-transcript fallback and marks the post-processing stage as Needs Attention.
- While post-processing is known to need attention, skip that stage for subsequent dictations instead of making requests known to fail.
- Clear Needs Attention when the relevant credential or model changes and the configuration validates successfully.
- Do not silently disable post-processing or change the user's selected provider or model.
- Treat Needs Attention as runtime validation state, not a persisted standalone `isConfigured` flag.

## First-run and settings experience

The app has no registration, login, or application account.

On first launch, show a configuration window. Also show or reopen provider setup on the first dictation attempt without a viable transcription configuration:

1. Show OpenAI as the supported transcription provider.
2. Request and securely store the user's OpenAI API key.
3. Allow selection of a supported OpenAI transcription model.
4. Validate the configuration with a lightweight test.
5. Ask the user to keep post-processing disabled or explicitly enable it.
6. If enabled, configure its provider and model independently. OpenAI is the only provider available in the initial version.

Settings must allow changing providers and models whenever no session is actively recording or processing.

The UI must clearly indicate whether audio is processed locally or uploaded.

Session configuration behavior:

- Create an immutable session configuration snapshot when recording starts.
- Snapshot the transcription provider, transcription model, language selection, post-processing mode/provider/model, and audio profile.
- Use that snapshot throughout recording, transcription, post-processing, and insertion.
- Make session-affecting Settings controls read-only while a session is recording or processing, with a concise explanation.
- Settings changes made while idle apply to the next recording.
- Resolve credentials securely when a provider request begins; do not copy API keys into persisted session configuration.
- In the transcription-failed state, allow the user to repair and validate the credential, provider, or model.
- An explicit Retry after repair uses the updated validated transcription configuration with the retained recording.

After onboarding, the persistent entry point is the menu-bar item. Its menu must provide at least:

- Current session status
- Start or Stop, as appropriate for the current state
- Cancel during any active session
- Open Settings
- Quit

Opening onboarding or Settings may show and activate a normal window, but the application must remain absent from the Dock and normal application switcher.

Quit behavior:

- Quit immediately without a confirmation dialog.
- If a session is active, apply the same best-effort cancellation and cleanup rules before terminating.
- Do not block application termination indefinitely while waiting for network cancellation or cleanup.
- Do not claim that quitting reverses provider-side processing or billing for a request that was already accepted.

### Permission experience

Onboarding explains why Microphone and Accessibility permissions are used, but opening onboarding must not trigger either system prompt.

Each permission has an explicit Enable action:

- **Microphone:** Enable requests system microphone authorization. Recording cannot start without it.
- **Accessibility:** Enable initiates the system trust flow required for automatic insertion.

Permission behavior:

- Show current permission status in onboarding and Settings.
- Derive status from the corresponding macOS authorization API; do not persist a separate granted flag.
- Recheck status before using the protected feature and when returning from System Settings.
- If the user skips Accessibility, keep dictation available in clipboard-only mode.
- If Accessibility is unavailable when insertion is attempted, leave the transcript on the clipboard and show the manual-paste fallback.
- If the user skips Microphone setup, request it just in time on the first attempt to start recording.
- If a permission was denied, explain the affected capability and provide an Open System Settings action rather than repeatedly triggering prompts.
- Permission denial must not block access to Settings, provider configuration, or an already-produced transcript.

## Recording and progress overlay

Show a compact pill-shaped overlay at the bottom center of the active display. Treat exact dimensions, spacing, and animation as implementation details to refine through use.

The overlay must:

- Use a non-activating `NSPanel`.
- Never become the key window or change the focused insertion target.
- Remain visible as the session moves from recording through transcription, optional post-processing, and insertion.
- Keep Cancel available until insertion completes.
- Allow its controls to be clicked without taking keyboard focus.

State-specific content:

- **Recording:** red recording indicator, elapsed time, Stop, and Cancel.
- **Transcribing:** progress indicator and a concise transcription status.
- **Post-processing:** progress indicator and a concise cleanup status.
- **Success:** brief confirmation, then dismiss automatically.
- **Raw fallback:** briefly indicate that cleanup was unavailable and the raw transcript was inserted.
- **Clipboard fallback:** explain that automatic insertion was unavailable and the transcript is ready to paste from the clipboard.
- **Recoverable capture failure:** show Transcribe Partial and Discard.
- **Transcription failure:** show the actionable Retry and Discard choices.

### Audible feedback

Provide short, distinguishable sound cues so the user can understand important state changes without looking at the overlay:

- Recording started
- Recording stopped and submitted
- Session cancelled
- Failure requiring user attention

Sound behavior:

- Enable sound cues by default and provide one Settings toggle to disable all of them.
- Use the current macOS output device and system output volume; do not add a separate volume control in the initial version.
- Finish the start cue before microphone capture begins so it cannot become part of the recording.
- Stop microphone capture before playing the stop or cancel cue.
- Do not play sounds for every internal processing-state transition.
- A raw post-processing fallback does not use the failure sound because insertion continues without user action.

## macOS integration

- `MenuBarExtra` for the persistent menu-bar entry
- Global shortcut service for starting and stopping dictation
- AVFoundation for microphone capture
- Speech framework when the future Apple transcription provider is implemented
- Non-activating `NSPanel` containing SwiftUI for the recording indicator
- `NSPasteboard` for clipboard operations
- Accessibility/CoreGraphics APIs for inserting text into another application
- Keychain for credentials

Microphone and Accessibility permissions must be requested only when their corresponding feature is first used, with a clear explanation.

## Audio capture

The initial OpenAI recording profile is:

- Container: M4A
- Codec: AAC
- Channels: mono
- Sample rate: 16 kHz
- Target bit rate: approximately 64 kbps

These values are internal configuration, not user preferences. Represent them as a typed recording profile supplied to `AudioRecorder`; do not scatter format constants through capture or provider code.

The recording profile must be replaceable from a single composition point. `AudioRecorder` must not assume that every future provider uses the OpenAI profile or even requires a file-based input.

Recording duration behavior:

- Discard recordings shorter than 500 milliseconds locally without making a provider request.
- Do not implement local silence detection or voice-activity detection in the initial version.
- Treat ten minutes as the hard maximum for one recording session.
- Show elapsed recording time in the recording overlay.
- Show a non-blocking warning shortly before the limit.
- At ten minutes, stop recording automatically and continue to transcription so the captured speech is preserved.
- Keep the maximum duration and warning threshold in the same typed internal configuration as the recording profile.
- Validate provider upload constraints before making a transcription request.

Input-device behavior:

- Resolve and use the current macOS default audio input at the start of every recording.
- Do not provide an application-specific microphone picker in the initial version.
- Display the active input device name in the recording overlay.
- Resolve the default again for each new session so changes made in macOS Sound settings take effect.
- If no input device is available before capture starts, show an actionable capture error and return to idle.
- If the input device becomes unavailable or capture fails while recording, stop capture and attempt to finalize the partial M4A.
- If the partial file is valid and at least 500 milliseconds long, offer Transcribe Partial and Discard. Do not upload it automatically.
- Keep a recoverable partial recording as the single active session until the user chooses Transcribe Partial, Discard, or Cancel.
- If the partial file cannot be finalized or validated, delete it and show an actionable capture error.

## Persistence and security

Use:

- `UserDefaults` / `@AppStorage` for non-sensitive preferences
- macOS Keychain for API keys
- Cache or temporary storage for recordings

Future local-model providers may add Application Support storage for app-managed models and security-scoped bookmarks for user-selected model files. Do not implement either until a provider requires them.

Do not introduce SQLite or SwiftData for the initial version. Add SwiftData later only if structured data such as transcription history, profiles, vocabulary, or usage statistics is required.

Security requirements:

- Never store API keys in UserDefaults, source files, SQLite, JSON, logs, or crash reports
- Display API keys masked, with Replace and Delete actions
- Do not log transcript or audio content by default
- Store recordings only in the application's cache or temporary directory
- Keep recorded audio only as long as required for transcription or an explicit transcription retry
- Delete temporary audio immediately after successful transcription, because post-processing does not require it
- Delete failed-session audio after discard or application termination
- Remove orphaned temporary recordings during application startup
- Do not expose recording format as a user preference; select a typed internal profile compatible with the configured transcription provider

## Architecture

The application has two logical layers in one process:

### Presentation

- Onboarding
- Settings
- Menu-bar controls
- Recording/progress overlay
- Errors and retry actions

### Dictation engine

- `DictationCoordinator`
- `AudioRecorder`
- `TranscriptionProvider`
- `PostProcessingProvider`
- `TextInsertionService`
- `GlobalShortcutService`
- `CredentialStore`
- `SettingsStore`

Expected session states:

```text
idle → recording
recording → idle                                      (cancel)
recording → transcribing                              (stop)
recording → captureFailed                             (device or capture failure)
captureFailed → transcribing or idle                  (transcribe partial or discard)
transcribing → postProcessing → inserting → idle      (cleanup enabled)
transcribing → inserting → idle                       (cleanup disabled)
transcribing → transcriptionFailed                    (transcription failure)
transcriptionFailed → transcribing or idle             (retry or discard)
postProcessing → inserting                            (success or raw fallback)
inserting → idle                                      (automatic insertion or clipboard fallback)
any non-idle state → idle                             (cancel)
```

Post-processing failure is not a terminal session state when a raw transcript exists.

UI code must not contain provider networking, audio capture, credential storage, or Accessibility logic.

## Delivery strategy

A separate `IMPLEMENTATION_PLAN.md` will define end-to-end vertical delivery slices when implementation planning begins. Each future slice must leave the application runnable and add a user-observable capability.

This is a delivery strategy, not a requirement to use strict backend-style Vertical Slice Architecture. Keep shared engine and macOS integration boundaries explicit rather than duplicating them per feature.

## Initial non-goals

- User accounts or authentication
- Proprietary backend
- Cross-device synchronization
- Subscription billing
- Transcription history
- Meeting recording, diarization, or speaker identification
- Model training
- Windows or Linux support
- Separate background daemon or XPC service
- App Store distribution, billing, notarization, or release packaging
- Launch at login for the development-stage initial version
- Custom post-processing prompts or cleanup instructions
- Cleanup intensity, tone, or writing-style presets
- Per-application cleanup profiles
- Bundled or user-selected local model runtimes

Launch at login is expected for a future distributable version, with an explicit user-controlled setting.
