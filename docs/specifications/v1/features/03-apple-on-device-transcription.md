# Apple On-Device Transcription

**Status:** Complete

## Summary

Add Apple On-Device as a transcription provider backed by the macOS 26
`SpeechTranscriber` API. The provider transcribes completed recordings on the
Mac without uploading audio, requiring an OpenAI credential, or incurring an
OpenAI transcription charge.

Apple On-Device and OpenAI remain explicit, independently selectable
transcription providers. The application must never upload a recording to
OpenAI as an automatic fallback from Apple On-Device.

This specification extends
`docs/specifications/v1/application.md` and supersedes the OpenAI-only and
global-language assumptions in
`docs/specifications/v1/features/01-tabbed-settings.md`.

## Product motivation

- Provide a transcription path with no per-request cloud transcription cost.
- Keep recorded voice audio on the Mac.
- Expect lower post-recording latency by removing upload and remote processing,
  without making a performance guarantee or adding latency telemetry.
- Preserve the existing dictation, post-processing, insertion, cancellation,
  and retained-recording recovery workflows.

## Goals

- Implement Apple `SpeechTranscriber` as a first-class transcription provider.
- Keep the app deployable on macOS 15 while making the provider usable only
  when the macOS 26 API and its on-device model are available.
- Discover supported locales and asset state at runtime.
- Install the selected locale asset explicitly during provider setup.
- Require a concrete locale for Apple transcription.
- Preserve provider choice and language choice independently for Apple and
  OpenAI.
- Keep OpenAI post-processing available after Apple transcription with a clear
  cloud data-flow disclosure.
- Fit the provider into the existing completed-file pipeline and recovery
  behavior.

## Non-goals

- Use `DictationTranscriber` or guarantee parity with macOS system Dictation.
- Support on-device transcription on macOS 15 through macOS 25.
- Add a legacy `SFSpeechRecognizer` fallback.
- Add live, streaming, or progressive transcription.
- Show partial transcripts while recording.
- Add automatic language detection for Apple.
- Support multiple simultaneously reserved Apple locale assets.
- Expose Apple model selection, custom models, alternative transcriptions,
  confidence values, or timestamps.
- Automatically switch providers after a failure.
- Disable or replace the existing OpenAI transcription provider.
- Add an on-device post-processing provider.
- Add latency measurement, benchmarks, telemetry, or a numeric performance
  acceptance criterion.
- Add an automated test target.
- Implement a dedicated migration flow for development-only configuration.

## Terminology

- **Apple On-Device:** the user-facing provider name.
- **SpeechTranscriber:** the macOS 26 Speech framework module used by the
  provider.
- **Locale asset:** the system-managed, locale-specific model installed through
  `AssetInventory`.
- **Available:** the current OS and device expose a usable
  `SpeechTranscriber`.
- **Configured:** Speech permission is granted, a supported locale is selected,
  and its required asset is installed.

## Platform availability

The application keeps its macOS 15 deployment target.

Apple On-Device is usable only when all of the following are true:

- The process is running on macOS 26 or later.
- `SpeechTranscriber.isAvailable` is true.
- The selected locale is present in the provider's runtime-supported locale
  catalog.
- Speech Recognition permission is granted.
- The required locale asset is installed and usable.

Compile-time and runtime availability checks must isolate every macOS 26 Speech
API reference. An Apple Silicon Mac or macOS 26 installation alone must not be
treated as proof that the provider is usable.

On macOS 15 through macOS 25, show Apple On-Device in Providers with:

- Unavailable status.
- A concise “Requires macOS 26 or later” explanation.
- No setup or permission action.

Exclude an unavailable Apple provider from the selectable Transcription
provider picker. On macOS 26, use the same unavailable presentation when
`SpeechTranscriber.isAvailable` is false, with device-appropriate explanatory
copy.

## Provider identity and capability

Add Apple On-Device as a provider with:

- Transcription capability only.
- On-device processing location.
- No authentication or credential.
- No custom-model support.
- No visible model picker.
- Completed M4A input compatibility.
- A runtime-derived explicit locale catalog.

The internal provider configuration may use a fixed provider-owned model
identifier to preserve the existing stage abstraction. That identifier is an
implementation detail and must not be presented as a user-selectable Apple
model.

The provider disclosure must state that:

- Completed recording audio is processed on this Mac.
- Audio is not uploaded for transcription.
- Locale assets may be downloaded from Apple during setup.
- Enabling cloud post-processing can still upload raw transcript text.

## Default provider behavior

Dedicated migration logic is not required.

For a new configuration:

- Default to Apple On-Device only when `SpeechTranscriber` is available and an
  equivalent supported locale exists for the user's preferred system locale.
- Otherwise default to OpenAI.
- Do not guess an unrelated Apple locale.

An existing decodable OpenAI configuration remains OpenAI. The feature must not
silently rewrite a saved provider choice.

OpenAI remains selectable on supported macOS 26 devices. Apple availability
does not make OpenAI a fallback-only provider.

## Language configuration

Language selection becomes provider-specific for transcription:

- Apple remembers one concrete locale.
- OpenAI independently remembers Automatic or its explicit language hint.
- Switching transcription providers restores that provider's last saved
  language selection.

Apple On-Device does not offer Automatic language detection. When Apple is
selected:

- Require a concrete locale before the configuration can be saved.
- Populate the picker from `SpeechTranscriber.supportedLocales`.
- Display locale names localized for the application's current locale.
- Preselect the closest supported equivalent of the user's preferred system
  locale when one exists.
- Preserve the exact selected supported locale identifier.
- Treat mixed-language behavior as model-dependent and make no guarantee.

OpenAI retains its existing Automatic and explicit-language behavior.

A session configuration snapshot must contain the resolved language for the
selected transcription provider. Later Settings changes must not alter an
active or retained session.

## Speech Recognition permission

Add `NSSpeechRecognitionUsageDescription` with copy that accurately states that
DictationApp uses Apple's on-device speech recognition to transcribe recorded
dictation.

Do not request Speech Recognition permission:

- At application launch.
- Merely by opening Settings.
- While OpenAI is the only provider being configured or used.

Request permission only after an explicit Apple setup action. Speech
Recognition permission is external system state and is not rolled back with
the Settings draft.

Expose the same system-derived permission state in:

- General → Permissions as the canonical permission location.
- Providers → Apple On-Device as contextual setup and repair state.

If permission is denied or restricted:

- Mark Apple On-Device Attention required.
- Prevent it from becoming the active saved transcription provider.
- Provide an action to open the relevant System Settings privacy pane.
- Do not select or invoke OpenAI automatically.

Refresh permission state when the application becomes active.

## Locale asset lifecycle

DictationApp manages one Apple locale reservation at a time.

During Apple setup or a locale change:

1. Confirm OS, device, permission, and locale support.
2. Request an `AssetInventory` installation supporting a
   `SpeechTranscriber` configured for the selected locale and the
   `.transcription` preset.
3. Show determinate progress when Apple exposes it and an indeterminate
   installing state otherwise.
4. Keep Save or Finish Setup unavailable until installation succeeds.
5. Validate that the asset is usable before committing the configuration.

Asset installation must never begin when the dictation shortcut is pressed.

When replacing an active Apple locale:

- Keep the previous reservation until the replacement asset installs and the
  Settings save succeeds.
- If installation or save fails, keep the previous saved configuration and
  reservation usable.
- After a successful save, release the app's previous locale reservation.

If the user discards a draft after installing a new asset, release a newly
created app reservation on a best-effort basis. macOS may retain the physical
asset because assets are system-managed and shared between applications.

If macOS later removes or invalidates the selected asset:

- Retain the saved Apple provider and locale.
- Mark the provider and Transcription stage Attention required.
- Prevent a new session from starting with an unusable configuration.
- Route repair to Apple setup so the asset can be reinstalled.

Do not silently release a working locale before its replacement is committed.

## First-run setup

On an eligible new installation:

1. Open Providers → Apple On-Device.
2. Explain on-device audio processing and the one-time locale asset download.
3. Preselect the closest supported preferred-system locale.
4. Request Speech Recognition permission only after the user starts setup.
5. Download and validate the selected locale asset.
6. Save Apple On-Device as the transcription provider and complete first run.

If Apple setup cannot complete or the user declines permission or asset
installation:

- Keep first-run configuration incomplete.
- Offer an explicit “Use OpenAI instead” route.
- Do not silently select OpenAI.

If no equivalent preferred locale exists, use the existing OpenAI first-run
route. Apple remains available for explicit setup with a supported locale.

## Providers settings

Providers must list both implemented providers:

- Apple On-Device.
- OpenAI.

The Apple detail page contains:

- On-device processing disclosure.
- OS and device availability.
- Speech Recognition permission status and action.
- Selected locale.
- Locale asset status.
- Explicit install, reinstall, or repair action as appropriate.
- Installation progress and actionable failure text.

It does not contain:

- Authentication controls.
- Disconnect or credential-removal actions.
- A model picker.
- A custom model field.
- Post-processing configuration.

Provider readiness is derived from current OS/device support, permission,
locale support, and installed asset state. Do not persist a standalone
configured flag.

## Transcription settings

The Transcription page:

- Offers Apple On-Device and OpenAI when each is eligible or provisionally
  configured in the current draft.
- Omits the Model row for Apple On-Device.
- Requires a concrete Apple locale.
- Retains the existing model and language controls for OpenAI.
- Shows the selected provider's actual processing-location disclosure.

If a saved provider later becomes unavailable, retain it visibly with Setup
required or Attention required and route the user to repair. Never replace it
automatically.

## Transactional Settings behavior

Provider and language choices remain part of the window-level Settings draft.
Speech permission and system asset installation are external side effects.

Saving an Apple configuration must:

- Validate availability, permission, selected-locale support, and asset state.
- Commit provider-specific language state atomically with the remaining app
  configuration.
- Preserve the previous working configuration if validation or persistence
  fails.
- Apply the locale reservation compensation rules defined above.

Closing or discarding a dirty window follows the existing Settings behavior.
External permission decisions are never reverted.

## Transcription runtime

Apple On-Device preserves the completed-file workflow:

1. Record and finalize the existing M4A artifact.
2. Resolve the immutable session provider and concrete locale.
3. Create `SpeechTranscriber` with the `.transcription` preset.
4. Verify the provider and locale asset remain usable.
5. Feed the completed audio file to `SpeechAnalyzer`.
6. Consume finalized transcriber results in order.
7. Concatenate their plain-text characters into one raw transcript.
8. Return that raw transcript through the existing provider interface.

Do not request:

- Volatile or fast results.
- Alternative transcriptions.
- Audio time ranges.
- Confidence attributes.

The app's existing whitespace normalization and empty-result behavior remain
authoritative. A blank or whitespace-only Apple result follows the existing
“No speech detected” path.

The existing ten-minute recording limit and minimum-duration behavior remain
unchanged.

## Cancellation and retained recordings

Cancellation must cancel and finish the active analyzer on a best-effort basis,
stop result consumption, and preserve the existing session-token protections.
After cancellation:

- No transcript may reach post-processing or insertion.
- The owned recording is deleted according to the existing lifecycle.
- No newer session may be mutated by stale Speech callbacks or results.

An Apple transcription failure retains the completed recording under the
existing recovery workflow.

Retry:

- Uses the same immutable provider and concrete locale unless the user applies
  an explicit validated repair.
- Never changes to OpenAI automatically.
- Rechecks current permission, support, and asset state.

Repair may explicitly switch the retained session from Apple to OpenAI only
when OpenAI supports the retained artifact and an equivalent concrete language.
The retained session must not silently change language.

## Failure mapping

Map Apple failures into the provider-neutral error taxonomy:

- Unsupported OS/device → unavailable configuration issue.
- Permission denied or restricted → provider-setup configuration issue.
- Unsupported or invalid locale → language configuration issue.
- Missing or unusable asset → provider-setup configuration issue with an
  install/repair action.
- Cancelled analyzer or task → cancellation.
- Temporary system-resource or analyzer interruption → transient failure when
  retry is safe.
- Invalid/unreadable audio → non-retryable operation failure.
- Empty finalized output → successful no-speech result.

User-facing failures must not expose framework error dumps. Logs may include
public error classifications but must never include audio, transcript text, or
locale asset payloads.

## Post-processing

Post-processing remains independently configured.

When Apple On-Device transcription and OpenAI post-processing are both active:

- Recording audio stays on-device.
- The raw Apple transcript is uploaded to OpenAI for cleanup.
- Existing OpenAI post-processing retry and raw-transcript fallback behavior
  remains unchanged.
- Settings and Data & Privacy copy must disclose this split data flow.

Selecting Apple must not automatically disable post-processing.

## Security and privacy

- Never upload Apple-transcribed recording audio.
- Never log audio, transcript text, Speech results, or permission prompt
  content.
- Keep temporary recording deletion behavior unchanged.
- Do not copy model assets into application-owned storage.
- Treat downloaded locale assets as system-managed resources.
- Do not claim the entire workflow is offline when cloud post-processing is
  enabled.

## Accessibility

- Permission, locale, installation, progress, readiness, and repair controls
  require meaningful accessibility labels, values, and hints.
- Installation progress must be conveyed without relying on color.
- Unavailable provider state must be announced with its reason.
- Keyboard navigation and focus routing must follow the existing Settings
  contract.

## Acceptance criteria

- The app still builds and launches with a macOS 15 deployment target.
- Apple On-Device is visible but unavailable below macOS 26 and cannot be
  selected for transcription.
- A supported macOS 26 device can grant Speech permission, select a concrete
  locale, install its asset, and save Apple as the transcription provider.
- Apple setup has no credential or model controls.
- Apple supports only a concrete locale and remembers it independently from
  OpenAI's language selection.
- A completed recording can be transcribed through `SpeechTranscriber` using
  the `.transcription` preset and inserted through the existing pipeline.
- Apple transcription makes no audio upload.
- Apple never falls back to OpenAI without an explicit validated user action.
- Missing permission, locale support, or asset state produces actionable
  provider/stage readiness and repair UI.
- Switching Apple locales does not release the previous working reservation
  before replacement setup and save succeed.
- OpenAI post-processing remains usable with Apple transcription and its
  transcript-upload boundary is disclosed.
- Cancellation, no-speech handling, retained-recording retry, and insertion
  behavior remain consistent with the existing application specification.
- Progressive transcription, alternatives, timestamps, custom Apple models,
  `DictationTranscriber`, and legacy macOS local recognition are absent.

## Manual verification

The implementation plan must cover manual verification for:

- macOS version and runtime availability gating.
- Permission grant, denial, and repair.
- Supported, unsupported, installed, and missing locale-asset states.
- First-run Apple setup and explicit OpenAI alternative.
- Switching providers and restoring provider-specific languages.
- Apple transcription with post-processing disabled and enabled.
- Cancellation during Apple analysis.
- Empty speech, analyzer failure, retained retry, and explicit provider repair.
- Settings discard and failed-save reservation compensation.
- Debug and Release builds.

Latency comparison or instrumentation is not required.
