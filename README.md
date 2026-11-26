# DictationApp

DictationApp is a native macOS menu-bar app that records your speech, transcribes it through a configurable provider, and inserts the result at the current text cursor. It supports optional transcript cleanup for punctuation and formatting.

You can transcribe and clean up text on your Mac or use your own OpenAI API
key for either stage. DictationApp has no separate account or backend service.

This project is developed through a specification-driven, AI-assisted engineering workflow. Requirements, implementation slices, and verification evidence are documented in [`docs/`](docs/).

## Features

- Full native Settings window with General, Transcription, Post-processing, and Providers destinations
- Configurable global shortcuts for toggle and hold-to-dictate recording
- Preferred microphone selection with automatic System Default fallback
- Native, non-activating recording overlay
- Provider and model selection for transcription
- Provider-neutral automatic or explicit language selection
- Independently configurable, optional transcript cleanup
- Provider-specific setup and readiness management
- Automatic insertion into the focused application
- Clipboard fallback when automatic insertion is unavailable
- Cancellation, retry, and partial-recording recovery
- Provider credentials stored in macOS Keychain

## Providers

Provider setup is separate from choosing which provider and model powers each processing stage:

- **Providers** manages provider-specific authentication, configuration, capabilities, and readiness.
- **Transcription** selects a capable, configured provider, a provider-specific model, and the global language preference.
- **Post-processing** can be disabled or configured independently with its own provider and model selection.

- **Apple On-Device** transcribes speech on the Mac on macOS 26 or later
  with a supported language asset.
- **Apple Intelligence** tidies text on eligible Macs with macOS 26 or later.
  It makes conservative wording changes. If local cleanup cannot edit a
  transcript safely or within the time limit, the app inserts the raw text.
- **OpenAI** supports both transcription and cleanup. When using GPT-6 Luna
  for cleanup, Fast mode is available as an opt-in at a higher token rate.

Settings changes are held together until **Save Changes** succeeds. Shortcut, provider credential, model, language, and post-processing changes are validated and committed as one operation, with best-effort rollback if a later step fails.

## Requirements

- Apple Silicon Mac
- macOS 15 or later
- Xcode 26.6 or later
- OpenAI API key when selecting OpenAI for either stage

Microphone permission is required for recording. Accessibility permission is optional and enables automatic text insertion.

## Build and run

1. Open `DictationApp.xcodeproj` in Xcode.
2. Select your Apple Development team under **Signing & Capabilities** if needed.
3. Build and run the **DictationApp** scheme.
4. In **Settings → Transcription**, choose a provider. For Apple On-Device,
   prepare the language asset in **Providers**. For OpenAI, add your API key
   in **Providers → OpenAI**.
5. In **Settings → Post-processing**, enable transcript cleanup if you want
   punctuation, formatting, and filler edits. Choose **Apple Intelligence**
   to clean up on the Mac, or **OpenAI** for cloud cleanup. Select
   **Save Changes**.

DictationApp runs in the menu bar and does not appear in the Dock.

## Usage

Use either global shortcut to dictate.

- Press **Option–Space** to start. Press it again to stop and transcribe.
- Hold **Control–Shift–Space** for a short dictation. Release **Space** to stop and transcribe.
- Press **Escape** to cancel an active session.

Change either shortcut or disable hold to dictate in **Settings → General**,
then select **Save Changes**.

After transcription, the app inserts the text at the currently focused cursor. If insertion fails or cannot be confirmed, the transcript remains on the clipboard for manual paste.

## Privacy

OpenAI receives completed audio after Stop when selected for transcription.
When selected for cleanup, it receives the raw transcript in a separate
request. Apple On-Device transcription and Apple Intelligence cleanup
process their inputs on the Mac. Provider credentials remain in macOS
Keychain. The app deletes temporary recordings after successful
transcription and excludes audio, transcripts, credentials, and clipboard
contents from its logs.
