# Repository Guidelines

## Project Structure & Module Organization

`DictationApp/` contains the macOS application, organized by responsibility:

- `App/` wires services, providers, and application lifecycle.
- `Domain/` defines configuration and session models.
- `Engine/` owns the dictation pipeline, recovery, and provider protocols.
- `Infrastructure/` implements audio, accessibility, clipboard, persistence, security, shortcuts, diagnostics, and OpenAI integration.
- `Presentation/` contains SwiftUI views and AppKit window controllers.
- `Resources/` and `Assets.xcassets/` hold bundled media and catalog assets.

The Xcode project is `DictationApp.xcodeproj`. Product specifications and implementation evidence live under `docs/specifications/` and `docs/plans/`; keep these synchronized when behavior changes.

## Build, Test, and Development Commands

- `open DictationApp.xcodeproj` opens the project for signing, running, and debugging.
- `xcodebuild -project DictationApp.xcodeproj -scheme DictationApp -configuration Debug build` performs a command-line Debug build.
- `xcodebuild -project DictationApp.xcodeproj -scheme DictationApp -configuration Release build` catches release-only compiler and concurrency issues.
- `git diff --check` detects whitespace errors before committing.

Use Xcode 26.6 or later with an Apple Silicon Mac running macOS 15+. Command-line builds require `xcode-select` to point to the full Xcode installation.

## Coding Style & Naming Conventions

Follow existing Swift conventions: four-space indentation, one primary type per file, `UpperCamelCase` types, and `lowerCamelCase` members. Name protocols and services by role (for example, `TranscriptionProvider` and `PermissionService`). Keep UI state mutations on `@MainActor`; strict concurrency checking is enabled, so make ownership and `Sendable` boundaries explicit. Prefer small SwiftUI views, dependency injection through initializers, and structured `OSLog` calls. Never log credentials, transcripts, audio, clipboard contents, or request bodies.

## Testing Guidelines

There is currently no automated test target. Every change must at least compile in Debug and Release. Manually exercise affected menu-bar, Settings, shortcut, recording/cancellation, provider failure, and clipboard/accessibility flows. Record significant verification results in the relevant `docs/plans/` file. If adding tests, create a `DictationAppTests` XCTest target and name files `<TypeName>Tests.swift`.

## Commit & Pull Request Guidelines

Recent history uses short, imperative, sentence-case subjects such as `Harden dictation runtime robustness`. Keep commits focused; use the body to explain behavior, architecture, and verification. Pull requests should summarize user-visible effects, link the relevant specification or issue, list build/manual-test evidence, and include screenshots for Settings, overlays, or other UI changes. Call out permission, Keychain, privacy, entitlement, or migration impacts explicitly.
