# DictationApp

DictationApp is a native macOS menu-bar app that records your speech, transcribes it through a configurable provider, and inserts the result at the current text cursor. It supports optional transcript cleanup for punctuation and formatting.

OpenAI is currently the only implemented provider. The app uses your own OpenAI API key and does not require a separate DictationApp account or backend service.

This project is developed through a specification-driven, AI-assisted engineering workflow. Requirements, implementation slices, and verification evidence are documented in [`docs/`](docs/).

## Features

- Full native Settings window with General, Transcription, Post-processing, and Providers destinations
- Global keyboard shortcut with transactional Save and rollback behavior
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

OpenAI currently supports both transcription and post-processing. The provider registry is designed to add providers with different capabilities, processing locations, authentication mechanisms, and custom Settings interfaces without exposing unimplemented providers in the UI.

Settings changes are held together until **Save Changes** succeeds. Shortcut, provider credential, model, language, and post-processing changes are validated and committed as one operation, with best-effort rollback if a later step fails.

## Requirements

- Apple Silicon Mac
- macOS 15 or later
- Xcode 26.6 or later
- OpenAI API key

Microphone permission is required for recording. Accessibility permission is optional and enables automatic text insertion.

## Build and run

1. Open `DictationApp.xcodeproj` in Xcode.
2. Select your Apple Development team under **Signing & Capabilities** if needed.
3. Build and run the **DictationApp** scheme.
4. Open **Settings → Providers → OpenAI** and enter your OpenAI API key.
5. Choose the transcription and optional post-processing configuration in their respective Settings destinations.

DictationApp runs in the menu bar and does not appear in the Dock.

## Usage

The default global shortcut is **Option–Space**:

- Press once to start recording.
- Press again to stop and transcribe.
- Press **Escape** to cancel an active session.

After transcription, the app inserts the text at the currently focused cursor. If insertion fails or cannot be confirmed, the transcript remains on the clipboard for manual paste.

## Privacy

With the currently implemented OpenAI provider, completed audio is uploaded only after recording stops. When OpenAI transcript cleanup is enabled, the raw transcript is sent in a separate request. Provider credentials remain in macOS Keychain. Temporary recordings are deleted after successful transcription, and transcripts, audio, credentials, and clipboard contents are not written to application logs.
