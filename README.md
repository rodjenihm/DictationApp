# DictationApp

DictationApp is a native macOS menu-bar app that records your speech, transcribes it with OpenAI, and inserts the result at the current text cursor. It supports optional transcript cleanup for punctuation and formatting.

The app uses your own OpenAI API key and does not require a separate account or backend service.

This project is developed through a specification-driven, AI-assisted engineering workflow. Requirements, implementation slices, and verification evidence are documented in [`docs/`](docs/).

## Features

- Global keyboard shortcut, configurable in Settings
- Native, non-activating recording overlay
- OpenAI transcription with automatic or explicit language selection
- Optional transcript cleanup
- Automatic insertion into the focused application
- Clipboard fallback when automatic insertion is unavailable
- Cancellation, retry, and partial-recording recovery
- API-key storage in macOS Keychain

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
4. Enter your OpenAI API key in Settings.

DictationApp runs in the menu bar and does not appear in the Dock.

## Usage

The default global shortcut is **Option–Space**:

- Press once to start recording.
- Press again to stop and transcribe.
- Press **Escape** to cancel an active session.

After transcription, the app inserts the text at the currently focused cursor. If insertion fails or cannot be confirmed, the transcript remains on the clipboard for manual paste.

## Privacy

Audio is uploaded to OpenAI only after recording stops. When transcript cleanup is enabled, the transcript is sent to OpenAI in a separate request. Temporary recordings are deleted after successful transcription, and transcripts, audio, credentials, and clipboard contents are not written to application logs.
