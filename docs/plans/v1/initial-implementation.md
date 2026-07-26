# DictationApp v1 Implementation Plan

## Baseline and decisions

The repository is a clean, buildable Xcode 26.6 SwiftUI project with one macOS target, a generated `Info.plist`, synchronized filesystem groups, App Sandbox enabled, and a deployment target of macOS 26.5. Building the existing target with `MACOSX_DEPLOYMENT_TARGET=15.0` and `ARCHS=arm64` succeeds, so the project will be converted in place rather than recreated.

### Verified platform facts

- SwiftUI `MenuBarExtra` supports menu-bar-only utilities, and Apple explicitly recommends `LSUIElement=true` to remove them from the Dock and application switcher. [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- Apple documents Accessibility API use as incompatible with App Sandbox. App Sandbox must therefore be disabled for v1 text insertion; Hardened Runtime remains enabled. [Apple: Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- Microphone status and prompting are available through `AVCaptureDevice.authorizationStatus(for:)` and `requestAccess(for:)`, and require `NSMicrophoneUsageDescription`. [Apple: Requesting capture authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- `AVCaptureAudioFileOutput` writes audio files and exposes encoding settings, fitting the required configurable M4A/AAC profile. [Apple: AVCaptureAudioFileOutput](https://developer.apple.com/documentation/avfoundation/avcaptureaudiofileoutput)
- A non-activating `NSPanel` can handle mouse controls without taking keyboard focus. [Apple: NSPanel.becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)
- `AXIsProcessTrustedWithOptions` provides the explicit Accessibility trust flow; `AXUIElement` exposes focused-element inspection and writable attributes. [Apple: AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- `NSPasteboard.changeCount` is explicitly intended for determining whether an application still owns the pasteboard. [Apple: NSPasteboard.changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)
- OpenAI’s completed-file transcription endpoint accepts M4A, supports the specified `gpt-4o-transcribe` models and language hints, and currently limits uploads to 25 MB. [OpenAI: Speech to text](https://developers.openai.com/api/docs/guides/speech-to-text)
- GPT-5 models use the Responses API for text generation. Responses are stored by default, so post-processing requests will set `store: false`. [OpenAI: Text generation](https://developers.openai.com/api/docs/guides/text-generation), [OpenAI: Responses storage](https://developers.openai.com/api/docs/guides/migrate-to-responses#messages-vs-items)

### Implementation recommendations

- Use only Apple frameworks plus direct `URLSession` HTTP adapters; add no package dependencies.
- Use native HIToolbox `RegisterEventHotKey` for the configurable global shortcut and session-scoped Escape interception. The current macOS SDK exposes exclusive registration, zero-modifier hotkeys, and `CopySymbolicHotKeys` for enabled system-reserved combinations.
- Use `AVCaptureSession`, the current default `AVCaptureDevice`, and `AVCaptureAudioFileOutput` rather than a microphone picker or audio engine abstraction.
- Keep recordings under an app-owned cache directory and remove all orphaned recordings at startup.
- Use direct `AXUIElementSetAttributeValue(kAXSelectedTextAttribute)` for automatic insertion. Do not synthesize Command–V after an unverified Accessibility write because that could duplicate text.
- Keep settings and provider catalogs lightweight; do not introduce dependency injection containers, repositories, persistence databases, or provider factories beyond the v1 composition root.

## Internal contracts

- `SessionConfiguration`: immutable value containing opaque transcription provider/model selections, language, post-processing selection, and typed `RecordingProfile`; never contains credentials.
- `DictationSessionState`: explicit state enum matching the specification, with associated artifact/error metadata only where required.
- `TranscriptionProvider`: validates provider configuration and transcribes a completed `AudioArtifact`.
- `PostProcessingProvider`: validates configuration and transforms raw text independently of transcription.
- `ProviderOperationFailure`: provider-neutral classification of cancellation, transient failure with optional retry delay, permanent configuration failure, and non-retryable operation failure.
- `AudioRecorder`: starts with a typed profile and resolved input device, stops/finalizes, cancels/deletes, and reports capture failure.
- `TextInsertionService`: returns `confirmed`, `unverified`, or `failed`; provider and presentation code never import Accessibility APIs.
- `CredentialStore`: read/replace/delete by provider credential reference; only OpenAI adapters resolve the API key when beginning a request.
- `GlobalShortcutService`: owns registration independently of the coordinator and emits semantic toggle/cancel actions.
- `SettingsStore`: wraps `UserDefaults` for non-sensitive preferences. It persists no `isConfigured` or post-processing “Needs Attention” flag.

The source tree will be organized under `App`, `Domain`, `Engine`, `Infrastructure`, and `Presentation`. OpenAI authentication, API identifiers, request/response structs, multipart encoding, and error decoding remain under `Infrastructure/OpenAI`.

## Vertical slices

### Slice 1 — Convert the existing target into a menu-bar utility shell

1. **User-visible outcome:** The app launches as a persistent menu-bar utility, opens a first-run setup shell, has no Dock or Command–Tab presence, and exposes status, Settings, and Quit.
2. **Included:** Lower target to macOS 15.0; restrict to arm64; preserve bundle ID/team/Hardened Runtime; disable App Sandbox; add `LSUIElement` and microphone usage text; replace the default `WindowGroup`; add non-removable `MenuBarExtra`; create one AppKit-hosted SwiftUI configuration window that can activate normally; immediate Quit.
3. **Excluded:** Actual settings persistence, credentials, permissions, shortcuts, recording, networking, overlay, and insertion.
4. **Components/files:** Existing `DictationApp.xcodeproj/project.pbxproj` and `DictationAppApp.swift`; new `App/AppModel.swift`; `Presentation/MenuBar/MenuBarContent.swift`; `Presentation/Configuration/ConfigurationWindowController.swift`.
5. **Frameworks/APIs:** SwiftUI `MenuBarExtra`; AppKit `NSWindowController`, `NSHostingController`, `NSApplication`.
6. **Dependencies:** Existing Xcode target only.
7. **Manual acceptance:** Debug and Release build for arm64/macOS 15; one menu-bar icon appears; no Dock icon or normal app-switcher entry; first launch shows setup; closing it leaves the app running; Settings reopens it; Quit terminates immediately.
8. **Risks:** `LSUIElement` activation behavior and window restoration must not accidentally restore a normal app window; App Sandbox must actually be absent from the built entitlement set.

### Slice 2 — Complete first-run configuration, preferences, and credentials

1. **User-visible outcome:** The user can enter and validate an OpenAI key, select transcription/language settings, explicitly keep cleanup disabled or enable and validate it, and reopen the same configuration from Settings.
2. **Included:** `UserDefaults` preferences; Keychain generic-password CRUD; masked credential state with Replace/Delete; first-run completion marker; OpenAI transcription catalog (`gpt-4o-transcribe` default, `gpt-4o-mini-transcribe`); Automatic plus provider-declared languages; post-processing disabled by default with `gpt-5-mini`/`gpt-5-nano`; curated/custom model UI; validation before committing a new credential or custom model; upload-boundary copy.
3. **Excluded:** User microphone recording, normal transcription, session coordination, retries, and insertion.
4. **Components/files:** `Domain/Configuration/*`; `Infrastructure/Persistence/SettingsStore.swift`; `Infrastructure/Security/KeychainCredentialStore.swift`; `Infrastructure/OpenAI/{OpenAIClient,OpenAIModelCatalog,OpenAIConfigurationValidator}.swift`; onboarding/settings views.
5. **Frameworks/APIs:** SwiftUI, Foundation `UserDefaults`/`URLSession`, Security `SecItem*`, AVFoundation for a bundled 0.75-second silent M4A validation fixture.
6. **Dependencies:** Slice 1 configuration window and composition root.
7. **Manual acceptance:** Key never appears unmasked or in defaults; valid configuration completes onboarding; invalid/inaccessible/custom-incompatible models cannot become active; replacing with an invalid key preserves the prior key; Delete makes transcription unconfigured; preferences survive relaunch; onboarding itself triggers no permission prompt.
8. **Risks:** Validation is a real provider call. UI must disclose that transcription validation uploads the bundled silent fixture and post-processing validation sends a minimal fixed text. Candidate keys remain only in transient UI memory until validation succeeds.

### Slice 3 — Permission flows and configurable global shortcut

1. **User-visible outcome:** Settings shows live Microphone and Accessibility status, explicit Enable/Open System Settings actions, and a configurable working Option–Space shortcut.
2. **Included:** Permission status derived on demand and rechecked when the app/settings reactivate; microphone prompt only from Enable or just-in-time start; Accessibility trust prompt only from Enable; clipboard-only mode when skipped; shortcut recorder; system-reserved shortcut detection through `CopySymbolicHotKeys`; exclusive registration; rollback to the previous shortcut on registration failure.
3. **Excluded:** Audio capture and insertion. Invoking the shortcut while otherwise configured reports that the recording engine is not yet available in this intermediate slice.
4. **Components/files:** `Infrastructure/Permissions/PermissionService.swift`; `Infrastructure/Shortcuts/{GlobalShortcutService,ShortcutRecorder}.swift`; permission and shortcut settings sections.
5. **Frameworks/APIs:** AVFoundation authorization APIs; ApplicationServices trust APIs; HIToolbox `RegisterEventHotKey`/`CopySymbolicHotKeys`; `NSWorkspace` for System Settings.
6. **Dependencies:** Slice 2 preferences and configuration viability.
7. **Manual acceptance:** Opening Settings causes no prompt; each Enable action triggers only its own flow; denied permissions show explanation and System Settings action; Option–Space works while another app is active; reserved/conflicting choices are rejected without losing the old shortcut; a relaunch restores registration.
8. **Risks:** System Settings privacy-pane deep links are not a stable documented contract; provide a root System Settings fallback plus textual navigation. If exclusive hotkey registration semantics change, surface an actionable conflict rather than silently accepting the shortcut.

### Slice 4 — Local capture, explicit session state, and sound cues

1. **User-visible outcome:** Menu and global shortcut start and stop a real local recording, display elapsed time/input device, play distinct cues, and return safely to idle.
2. **Included:** Explicit coordinator state; immutable session snapshot at start; default input resolution per session; M4A/AAC mono 16 kHz/~64 kbps capture; 500 ms minimum; 9:30 warning and 10:00 automatic stop; typed profile at the composition root; start cue fully completed before capture; stop/cancel/failure cues after capture stops; sound toggle enabled by default.
3. **Excluded:** Overlay, cloud upload, transcription, partial recovery, clipboard, and insertion. A successfully finalized recording is briefly acknowledged and deleted in this intermediate slice.
4. **Components/files:** `Engine/DictationCoordinator.swift`; `Domain/{DictationSessionState,SessionConfiguration,RecordingProfile,AudioArtifact}.swift`; `Infrastructure/Audio/{AVFoundationAudioRecorder,SoundCuePlayer,RecordingFileStore}.swift`.
5. **Frameworks/APIs:** `AVCaptureSession`, `AVCaptureDevice`, `AVCaptureDeviceInput`, `AVCaptureAudioFileOutput`, `AVURLAsset`, `ContinuousClock`.
6. **Dependencies:** Slice 3 shortcut/permissions and Slice 2 settings.
7. **Manual acceptance:** Menu and Option–Space perform the same toggle; a second press stops; processing-state presses are ignored; active input name is correct; audio metadata shows M4A/AAC/mono/16 kHz near 64 kbps; sub-500 ms recordings never leave idle artifacts; warning and auto-stop work with temporarily shortened development constants before restoring production values; sound toggle suppresses every cue.
8. **Risks:** Hardware input commonly runs at 48 kHz, so output settings and finalized asset metadata must confirm re-encoding. Cue playback and capture sequencing must avoid capturing the start cue.

### Slice 5 — Non-activating overlay and cancellation-safe cleanup

1. **User-visible outcome:** A compact bottom-center overlay follows recording/finalization without stealing focus, and Stop/Cancel/Escape work while the user changes apps or cursor position.
2. **Included:** Non-activating pill `NSPanel`; active display chosen from the pointer location at session start; red indicator, elapsed time, input device, Stop/Cancel; warning state; dynamically registered modifierless Escape only while non-idle; immediate recorder stop, task cancellation, transcript/artifact disposal, and idle transition; startup orphan cleanup.
3. **Excluded:** Transcription/progress states not yet implemented; capture recovery choices; text insertion.
4. **Components/files:** `Presentation/Overlay/{OverlayPanel,OverlayWindowController,OverlayView,OverlayViewState}.swift`; coordinator cancellation expansion; recording-file startup cleanup.
5. **Frameworks/APIs:** AppKit `NSPanel`, `NSScreen`, `NSEvent.mouseLocation`, SwiftUI hosting; HIToolbox session-scoped Escape hotkey.
6. **Dependencies:** Slice 4 state/capture and Slice 3 shortcut service.
7. **Manual acceptance:** Starting from TextEdit leaves TextEdit’s caret/focus intact; overlay buttons respond without activating DictationApp; switching apps leaves focus with the new app; Escape cancels and does not propagate; menu Cancel behaves identically; cancellation removes the M4A and allows an immediate new session.
8. **Risks:** SwiftUI controls hosted in `NSPanel` must not request key status. If Escape cannot be registered exclusively, recording must not start and the app must report the conflict because non-propagating Escape is a required cancellation path.

### Slice 6 — Provider-neutral completed-file OpenAI transcription

1. **User-visible outcome:** Stopping uploads the finalized recording, displays transcription progress, and leaves the raw transcript on the clipboard for manual paste; failures retain the recording for Retry or Discard.
2. **Included:** `TranscriptionProvider`; completed-file-only OpenAI multipart request; opaque catalog-to-API model mapping; optional language hint; credential resolution at request start; M4A/size validation against the current 25 MB provider limit; empty-result handling; transient retries; retained failed artifact; explicit Retry/Discard; cancellation of `URLSessionTask`; delete audio immediately after successful transcription.
3. **Excluded:** Post-processing and Accessibility insertion. Successful non-empty text intentionally ends in clipboard-only mode in this slice.
4. **Components/files:** `Engine/Providers/{TranscriptionProvider,ProviderOperationFailure,RetryExecutor}.swift`; `Infrastructure/OpenAI/OpenAITranscriptionProvider.swift` plus private request/error DTOs; coordinator/overlay transcription states.
5. **Frameworks/APIs:** Foundation `URLSession` with ephemeral configuration; `NSPasteboard` string write; OpenAI `/v1/audio/transcriptions`.
6. **Dependencies:** Finalized artifacts from Slice 4 and overlay/cancellation from Slice 5.
7. **Manual acceptance:** Both curated transcription models work; Automatic omits language and an explicit language sends its mapped hint; no request occurs before stop or after pre-upload cancellation; empty/whitespace output leaves clipboard unchanged and shows “No speech detected”; offline/timeout failures retry at most twice; exhausted failure blocks new recordings until Retry or Discard; successful Retry deletes the file.
8. **Risks:** Build multipart bodies in memory because the ten-minute profile is only about 5 MB, avoiding another temporary multipart file. Never log body data, transcript, authorization headers, or provider error bodies containing sensitive content.

**Retry parameters:** Three total attempts; retry HTTP 408/429/5xx and transient transport/timeouts unless OpenAI’s error code marks the failure permanent; parse seconds or HTTP-date `Retry-After`; otherwise use full-jitter exponential delays based on 1 s, capped at 8 s; cap cumulative retry waiting at 30 s. Use a 120 s request timeout for transcription. Treat invalid credentials, unsupported/inaccessible models, malformed requests, cancellation, and quota-exhaustion errors as non-retryable.

### Slice 7 — Recoverable capture failures and configuration repair

1. **User-visible outcome:** A usable partial recording can be explicitly transcribed or discarded, while permanent transcription configuration failures offer Settings, Retry, and Discard.
2. **Included:** Device-disconnection/capture-error observation; stop and finalize partial M4A; validate audio track and duration; `captureFailed` state; Transcribe Partial without automatic upload; delete invalid/short partials; permanent error classification; transcription repair while the failed session remains active; single failed/partial session constraint; quit cleanup.
3. **Excluded:** Post-processing recovery and session history.
4. **Components/files:** Audio recorder delegate/disconnection handling; `Engine/Recovery/FailedSessionContext.swift`; overlay/menu recovery actions; restricted Settings repair presentation.
5. **Frameworks/APIs:** AVFoundation recording delegate and device notifications; `AVURLAsset` async duration/track loading.
6. **Dependencies:** Slice 6 transcription and Slice 5 overlay.
7. **Manual acceptance:** Disconnecting or disabling the active input produces Transcribe Partial only for a valid ≥500 ms file; no partial is uploaded automatically; Discard/Cancel removes it; invalid partials are deleted with an actionable error; an invalid key/model failure opens repair UI; validated repair followed by Retry succeeds without rerecording; another recording cannot start until resolution.
8. **Risks:** On repair Retry, only the transcription provider/model selection and freshly resolved credential are replaced. The original language, audio profile, and post-processing snapshot remain immutable. This narrowly implements the specification’s repair exception without allowing unrelated Settings changes to mutate the session.

### Slice 8 — Independent optional OpenAI post-processing and raw fallback

1. **User-visible outcome:** Users who explicitly enabled cleanup receive cleaned text; transient or invalid cleanup never loses the raw transcript or blocks insertion/clipboard delivery.
2. **Included:** Independent `PostProcessingProvider`; OpenAI Responses request with `store:false`; built-in immutable cleanup instructions; raw transcript treated as untrusted data; three-attempt retry policy; centralized output validation; raw fallback status; permanent Needs Attention runtime state; automatic skipping of known-bad cleanup until relevant validated configuration changes.
3. **Excluded:** Custom prompts, intensity/tone controls, voice commands, per-app profiles, or model-driven cleanup decisions.
4. **Components/files:** `Engine/Providers/PostProcessingProvider.swift`; `Domain/PostProcessingOutputPolicy.swift`; `Infrastructure/OpenAI/OpenAIPostProcessingProvider.swift` and private Responses DTOs; cleanup Settings/status UI.
5. **Frameworks/APIs:** Foundation `URLSession`; OpenAI `/v1/responses`.
6. **Dependencies:** Raw transcript from Slice 6 and Settings from Slice 2.
7. **Manual acceptance:** Disabled mode makes no cleanup call; each curated model works independently of the transcription model; cleanup preserves language/meaning and returns only text; empty, wrapped, or implausibly expanded output falls back; transient exhaustion inserts/copies raw text without a modal; invalid key/model marks Needs Attention and subsequent sessions skip requests; validated key/model replacement clears attention.
8. **Risks:** Prompt injection cannot be eliminated purely by delimiters. Keep transformation instructions in the Responses `instructions` field, serialize raw text as a distinct input data field, expose no tools, and validate output before use.

**Output policy:** Trim external whitespace while preserving internal paragraphs; reject empty output; reject newly introduced preambles, headings, enclosing quotes, or code fences; reject output longer than `max(rawCharacterCount + 256, ceil(rawCharacterCount × 1.5))`. Derive `max_output_tokens` centrally from this bound, clamped to 64–4096. Use a 60 s request timeout.

### Slice 9 — Clipboard preservation and Accessibility insertion

1. **User-visible outcome:** Final text is inserted into the element focused at insertion time when possible; otherwise it remains ready for manual paste without destroying newer clipboard contents.
2. **Included:** Best-effort materialization of all pasteboard items/types; ownership change count; final-text clipboard write; focused element resolution only after processing; selection replacement; boundary spacing; direct AX insertion; `Confirmed`/`Unverified`/`Failed`; guarded restoration; clipboard fallback messaging; cancellation rollback while still owner.
3. **Excluded:** Remembering the original app/caret, synthesized Command–V fallback, undo/removal after completed insertion, clipboard persistence or semantic inspection.
4. **Components/files:** `Infrastructure/Clipboard/{ClipboardSnapshot,ClipboardTransaction}.swift`; `Infrastructure/Accessibility/AccessibilityTextInsertionService.swift`; `Domain/TextInsertionOutcome.swift`; coordinator/overlay insertion states.
5. **Frameworks/APIs:** `NSPasteboard`/`NSPasteboardItem`; ApplicationServices `AXUIElementCreateSystemWide`, focused element, selected text/range/value attributes, settable checks, and attribute writes.
6. **Dependencies:** Final text from Slice 8 or raw text from Slice 6; Accessibility status from Slice 3.
7. **Manual acceptance:** Empty target and beginning caret insert unchanged text; selections are replaced; switching apps/carets during processing changes the destination; adjacent word characters gain exactly one space; punctuation/whitespace/newlines gain none; confirmed insertion restores a still-owned mixed-type clipboard snapshot; changing the clipboard during processing prevents restoration; denied AX/no writable target leaves final text and displays manual-paste fallback; unverified writes leave the transcript available.
8. **Risks:** Accessibility implementations differ substantially between native and web/editor controls. Return Unverified after a successful write without sufficient readback and never attempt a second insertion. Use UTF-16 ranges for AX values and define word-forming boundaries as Unicode letters, marks, decimal digits, or connector punctuation.

### Slice 10 — Cross-stage cancellation and state-machine hardening

1. **User-visible outcome:** Cancel behaves consistently during recording, transcription, cleanup, and insertion preparation, with no late actions from the cancelled session.
2. **Included:** One structured pipeline task per session; unique session token/generation guard on every asynchronous completion; best-effort network cancellation; immediate recorder stop; file deletion; in-memory transcript release; clipboard rollback if still owned; ignored stale callbacks; immediate return to idle; settings lock during active recording/processing.
3. **Excluded:** Provider-side request retraction, billing reversal, or undoing text already inserted.
4. **Components/files:** Coordinator transition reducer and cancellation path; pipeline task ownership; Settings read-only bindings and explanation; insertion transaction cancellation hook.
5. **Frameworks/APIs:** Swift structured concurrency and task cancellation; existing AVFoundation, URLSession, pasteboard, and Accessibility services.
6. **Dependencies:** All operational services from Slices 4–9.
7. **Manual acceptance:** Cancel during each visible stage; rapidly cancel and start a new session; delayed responses from the old session never change state, clipboard, overlay, or target; settings are read-only while processing but transcription repair remains available in failed state; cancellation after completed insertion does not remove inserted text.
8. **Risks:** AVFoundation and Accessibility calls are not uniformly cancellation-aware. Session tokens—not task cancellation alone—must prevent late side effects.

### Slice 11 — Final v1 integration and polish

1. **User-visible outcome:** The complete menu-bar dictation workflow is coherent, actionable, privacy-explicit, and stable across relaunch, failures, application switching, and quitting.
2. **Included:** Final menu state/actions; all overlay states; status timing; provider upload disclosures; no-speech status; raw fallback; clipboard/unverified fallback; actionable configuration/capture/transcription failures; startup orphan removal; bounded quit cleanup; all Settings locks and validation states; accessibility labels and keyboard navigation in normal Settings windows.
3. **Excluded:** Every listed v1 non-goal, including Apple transcription, other providers, realtime/local models, history, launch at login, distribution, voice commands, custom prompts, presets, and profiles.
4. **Components/files:** Existing presentation/coordinator composition; final strings/assets; privacy-conscious `Logger` categories containing only state/error classifications, never audio/transcript/key/clipboard content.
5. **Frameworks/APIs:** Existing stack only; no new infrastructure.
6. **Dependencies:** Slices 1–10.
7. **Manual acceptance:** Exercise first run, relaunch, configuration loss, both models, Automatic/explicit language, cleanup on/off/fallback/Needs Attention, short/maximum/partial recordings, every cancel point, retry/discard, successful/failed/unverified insertion, clipboard races, multiple displays, input-device changes, no-device startup, permission denial/recovery, shortcut conflicts, and quit from every non-idle state.
8. **Risks:** TCC permissions are code-signature sensitive; use the stable bundle ID and normal development signing during final manual verification. Run final compatibility verification on actual macOS 15 Apple Silicon hardware or a suitable VM, not only the current macOS 26.5 host.

**Final display timing:** success 1.2 s; no-speech 2 s; raw-cleanup fallback 2.5 s; clipboard/unverified fallback 6 s with Dismiss; recoverable failures remain until the user acts. Quit performs bounded local cleanup and does not wait indefinitely for provider cancellation.

## Verification policy

No automated test target is introduced by this plan. Every slice must build in Debug and Release and satisfy its listed manual acceptance criteria before beginning the next slice. Repository-tracked artifacts must remain absent from build output; Derived Data stays outside the repository.

## Recommended first implementation slice

Start with **Slice 1 — Convert the existing target into a menu-bar utility shell**.

### Exact completion criteria

- Existing project is edited in place; no target or project recreation.
- Debug and Release target macOS 15.0 and arm64.
- Hardened Runtime remains enabled; App Sandbox is disabled.
- Generated `Info.plist` contains `LSUIElement=true` and a microphone usage description.
- Default `WindowGroup` and “Hello, world” view no longer drive the lifecycle.
- A non-removable `MenuBarExtra` shows current status, disabled/unavailable Start, Open Settings, and Quit.
- First launch opens the SwiftUI setup shell in a normal activatable AppKit window.
- Closing setup leaves the menu-bar process running.
- Reopening Settings works without restoring a Dock icon or normal Command–Tab presence.
- Quit terminates immediately.
- Debug and Release builds succeed with no source changes outside this slice.
- The repository remains free of Derived Data and unrelated modifications.

### Prerequisites

- The existing Xcode 26.6 toolchain is sufficient; macOS 15 targeting has already been compile-verified.
- The existing bundle ID, development team, synchronized project group, and Hardened Runtime will be retained.
- The necessary project decision is to accept a **non-sandboxed v1 build**, because Accessibility insertion is incompatible with App Sandbox. This matches the specification’s personal-development/non–App Store scope.
- A valid OpenAI API key with usable billing/access is needed beginning with Slice 2 validation, not for Slice 1.
- Actual macOS 15 Apple Silicon runtime access is required before final v1 compatibility signoff, but it does not block the first slice.
