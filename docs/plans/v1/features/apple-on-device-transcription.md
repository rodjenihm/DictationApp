# Apple On-Device Transcription Implementation Plan

**Status:** Complete

## Source specification

Implement
`docs/specifications/v1/features/apple-on-device-transcription.md`.

This plan adds Apple On-Device incrementally while preserving the macOS 15
deployment target, the existing completed-file coordinator, and transactional
Settings behavior.

## Current architecture

- `ProviderID`, `AppConfiguration`, and `StageConfiguration` own persisted
  provider/model selection.
- `ProviderRegistry` maps provider IDs to runtime providers and type-erased
  Settings modules.
- `TranscriptionProvider` accepts a completed `AudioArtifact`, model selection,
  and language selection.
- `ConfigurationViewModel` owns the shared Settings draft and currently stores
  one global transcription language.
- `ProviderSettingsModule` owns provider readiness, validation, transactional
  commit/rollback, and provider detail UI.
- `PermissionService` owns microphone and Accessibility system state.
- `SettingsStore` persists `AppConfiguration` as JSON.
- Xcode uses file-system-synchronized groups, so new source files under
  `DictationApp/` are included without manual project-file membership edits.
- The target uses Swift 5 language mode with complete strict concurrency,
  approachable concurrency, and MainActor default isolation.

## Implementation principles

- Gate every Speech 26 symbol behind `#available(macOS 26, *)`.
- Keep UI and Settings mutation on MainActor.
- Use Speech framework Sendable values and the `SpeechAnalyzer` actor directly;
  do not introduce `@unchecked Sendable`.
- Keep provider-specific Speech types inside Infrastructure.
- Preserve immutable session snapshots and provider-neutral coordinator
  behavior.
- Do not add automated tests; verify with Debug/Release builds and focused
  manual checks.

## Slice 1 — Domain and persistence

### Provider identity

Update `DictationApp/Domain/Configuration/AppConfiguration.swift`:

- Add `ProviderID.appleOnDevice`.
- Use “Apple On-Device” as its display name.
- Add a fixed internal Apple model identifier for compatibility with the
  existing stage model abstraction.

### Provider-specific language

Replace the single stored transcription language with a dictionary keyed by
`ProviderID`:

- Keep `configuration.language` as the active-provider computed accessor so
  coordinator call sites remain provider-neutral.
- Add accessors to read and write a language for a specific provider.
- Seed Apple with a placeholder explicit locale until runtime setup resolves a
  supported default.
- Seed OpenAI with `.automatic`.
- Update structural validation so Apple cannot save Automatic.

Dedicated migration code is intentionally omitted. An undecodable
development-only configuration falls back to the new default.

### Dynamic descriptor metadata

Update the type-erased provider Settings wrapper so `descriptor` is read
dynamically from the underlying module. Apple locale metadata is asynchronous
and must update after initial construction.

## Slice 2 — Speech infrastructure

Add `DictationApp/Infrastructure/AppleSpeech/AppleSpeechService.swift` with
provider-neutral value snapshots for:

- OS/device availability.
- Supported and installed locale identifiers.
- Current asset status.
- Suggested locale equivalent to the user's preferred locale.
- Installation progress.

The service must:

- Return a stable unavailable snapshot below macOS 26.
- Query `SpeechTranscriber.isAvailable`, `supportedLocales`, and
  `installedLocales` on macOS 26.
- Configure `SpeechTranscriber(locale:preset: .transcription)`.
- Reserve/install through `AssetInventory`.
- Release an app reservation on request.
- Open the completed M4A with `AVAudioFile`.
- Run `SpeechAnalyzer`, consume finalized results, and return ordered plain
  text.
- Normalize cancellation and map Speech/AVFoundation failures without exposing
  framework dumps.

Do not request progressive, fast, alternative, timestamp, or confidence output.

Add `DictationApp/Infrastructure/AppleSpeech/AppleOnDeviceTranscriptionProvider.swift`:

- Conform to `TranscriptionProvider`.
- Reject Automatic language.
- Ignore the fixed internal model value.
- Recheck availability, locale support, and installed asset status on every
  call.
- Map missing setup to scoped provider-neutral configuration failures.
- Return the completed transcript string.

## Slice 3 — Permission integration

Update `DictationApp/Infrastructure/Permissions/PermissionService.swift`:

- Add a Speech Recognition permission status.
- Expose status, explicit request, and System Settings navigation.
- Never request permission during state refresh.
- Keep the existing microphone protocol used by the coordinator intact.

Update both build configurations in
`DictationApp.xcodeproj/project.pbxproj` with
`INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`.

## Slice 4 — Apple provider Settings module

Add
`DictationApp/Presentation/Configuration/AppleOnDeviceProviderSettingsModule.swift`.

The module owns:

- Availability and locale snapshots.
- Saved and candidate locale.
- Asset status.
- Permission state.
- Installation state/progress/failure.
- The previous/new reservation needed for compensation.

Its descriptor declares:

- Transcription only.
- On-device processing.
- No model catalog or custom model.
- Concrete runtime locale catalog.
- M4A compatibility.

Its detail view presents:

- Availability and permission.
- On-device/audio-local disclosure.
- Candidate locale.
- Asset status.
- Install, reinstall, or System Settings actions.
- Accessible progress and failure state.

Validation requires availability, granted permission, supported concrete
locale, and installed asset. Commit/rollback/did-save implement the reservation
rules:

- Never release the saved locale before the new asset is installed and
  application persistence succeeds.
- Release the previous locale after successful save.
- Release a newly reserved draft locale on discard/rollback when safe.

## Slice 5 — Settings draft and views

Update `ConfigurationViewModel`:

- Track language selections per provider.
- Restore each provider's previous language when switching.
- Refresh Apple module and Speech permission state when the app becomes active.
- Route first run to Apple when the module reports a supported suggested
  locale; otherwise retain the OpenAI route.
- Keep explicit “Use OpenAI instead” navigation available from Apple setup.
- Validate that Apple uses a concrete language.

Update `ConfigurationStageViews.swift`:

- Omit the Model row when the selected provider exposes no selectable models.
- Omit Automatic from Apple language choices.
- Keep OpenAI's existing model/custom-model/Automatic behavior.

Update `ConfigurationGeneralView.swift`:

- Add Speech Recognition to Permissions as the canonical status/action row.
- Show it only where the OS can expose the feature or Apple is present as an
  unavailable provider.

Update provider views/readiness presentation:

- List Apple even when unavailable.
- Exclude unavailable/unconfigured Apple from the Transcription picker unless
  provisionally configured in the draft.
- Announce unavailability and installation state accessibly.

## Slice 6 — Composition and defaults

Update `AppModel`:

- Construct the shared Apple Speech service.
- Register Apple Settings and transcription provider before OpenAI.
- Refresh Apple runtime state during application activation.
- Keep OpenAI post-processing registration unchanged.

Choose the effective first-run default after the asynchronous Apple support
snapshot is available:

- Apple only when SpeechTranscriber is available and an equivalent preferred
  locale exists.
- OpenAI otherwise.
- Never silently switch a completed saved configuration.

## Slice 7 — Recovery and privacy integration

Verify existing coordinator behavior remains provider-neutral:

- Apple failures retain the completed recording.
- Retry uses the immutable provider/language snapshot.
- Repair can select another compatible configured provider explicitly.
- Cancellation suppresses stale results and deletes the owned artifact.
- Empty Apple output enters the existing no-speech path.

Update configuration-aware privacy copy if any current text assumes OpenAI-only
transcription. Apple transcription plus OpenAI post-processing must clearly
state that audio remains local while raw transcript text is uploaded.

## Verification

### Static/build

- Run `git diff --check`.
- Build Debug:
  `xcodebuild -project DictationApp.xcodeproj -scheme DictationApp -configuration Debug build`
- Build Release:
  `xcodebuild -project DictationApp.xcodeproj -scheme DictationApp -configuration Release build`
- Resolve all compile errors and new warnings caused by the feature.

### Focused manual verification

On macOS 26:

- Apple appears in Providers without credentials or a model picker.
- Permission is not requested on launch or Settings open.
- Explicit setup requests permission and supports denial/repair.
- Supported locales load and Automatic is absent for Apple.
- Asset install progress and failure are actionable.
- Saving Apple enables it in Transcription.
- Switching to OpenAI restores its Automatic language and model.
- Switching back restores the Apple locale.
- A completed recording transcribes and inserts with Apple.
- OpenAI post-processing works after Apple transcription.
- Cancelling during Apple analysis returns to idle without insertion.
- Missing asset causes repair rather than OpenAI fallback.
- Explicit provider repair retains the recording and requires Retry.

Compatibility:

- Confirm macOS 15 deployment remains configured.
- Inspect the below-macOS-26 UI path to ensure Apple is unavailable and cannot
  be selected.

No latency benchmark or automated test target is required.

## Completion evidence

Completed on 2026-07-31:

- `git diff --check` passed.
- The Debug build passed with Xcode 26.6 on macOS 26.5.2.
- The Release build passed with whole-module optimization and complete strict
  concurrency enabled.
- The signed Release artifact passed `codesign --verify --deep --strict`.
- The built application retains `LSMinimumSystemVersion` 15.0 and contains the
  Speech Recognition privacy usage description.
- Static review confirmed that macOS 26 Speech symbols are availability-gated,
  Apple uses `.transcription`, Automatic is excluded, provider-specific
  languages survive switching, and Apple failures do not route to OpenAI.

Live permission, asset-download, transcription, insertion, cancellation, and
repair interaction were not performed because they require changing the
current user's macOS permission, asset, and application configuration state.
Those checks remain in the focused manual-verification list above. No latency
measurement was performed, as required by the specification.
