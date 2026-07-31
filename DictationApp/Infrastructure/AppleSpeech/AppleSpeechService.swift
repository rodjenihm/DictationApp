import AVFoundation
import Foundation
import Speech

enum AppleSpeechAvailability: Equatable, Sendable {
    case requiresMacOS26
    case unavailableOnDevice
    case available
}

enum AppleSpeechAssetState: Equatable, Sendable {
    case unsupported
    case supported
    case downloading
    case installed
}

struct AppleSpeechLocale: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
}

struct AppleSpeechSupportSnapshot: Equatable, Sendable {
    let availability: AppleSpeechAvailability
    let supportedLocales: [AppleSpeechLocale]
    let installedLocaleIDs: Set<String>
    let suggestedLocaleID: String?

    static let requiresMacOS26 = AppleSpeechSupportSnapshot(
        availability: .requiresMacOS26,
        supportedLocales: [],
        installedLocaleIDs: [],
        suggestedLocaleID: nil
    )
}

enum AppleSpeechServiceError: LocalizedError, Sendable {
    case unavailable
    case unsupportedLocale
    case reservationUnavailable
    case assetMissing
    case invalidAudio
    case installationFailed
    case temporarilyUnavailable
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple On-Device transcription is unavailable on this Mac."
        case .unsupportedLocale:
            "The selected language is not supported by Apple On-Device transcription."
        case .reservationUnavailable:
            "This Mac cannot reserve another Apple transcription language asset."
        case .assetMissing:
            "The selected Apple transcription language asset is not installed."
        case .invalidAudio:
            "The completed recording could not be opened for Apple transcription."
        case .installationFailed:
            "The Apple transcription language asset could not be installed."
        case .temporarilyUnavailable:
            "Apple On-Device transcription is temporarily unavailable."
        case .analysisFailed:
            "Apple On-Device could not transcribe the recording."
        }
    }
}

@MainActor
final class AppleSpeechService {
    func supportSnapshot() async -> AppleSpeechSupportSnapshot {
        guard #available(macOS 26.0, *) else {
            return .requiresMacOS26
        }

        guard SpeechTranscriber.isAvailable else {
            return AppleSpeechSupportSnapshot(
                availability: .unavailableOnDevice,
                supportedLocales: [],
                installedLocaleIDs: [],
                suggestedLocaleID: nil
            )
        }

        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let preferredLocale =
            Locale.preferredLanguages.first.map(Locale.init(identifier:))
                ?? Locale.current
        let suggested =
            await SpeechTranscriber.supportedLocale(
                equivalentTo: preferredLocale
            )

        return AppleSpeechSupportSnapshot(
            availability: .available,
            supportedLocales:
                supported.map {
                    AppleSpeechLocale(
                        id: $0.identifier,
                        displayName:
                            Locale.current.localizedString(
                                forIdentifier: $0.identifier
                            )
                            ?? $0.identifier
                    )
                },
            installedLocaleIDs: Set(installed.map(\.identifier)),
            suggestedLocaleID: suggested?.identifier
        )
    }

    func assetState(
        for localeIdentifier: String
    ) async -> AppleSpeechAssetState {
        guard #available(macOS 26.0, *) else {
            return .unsupported
        }
        guard
            SpeechTranscriber.isAvailable,
            let locale = await supportedLocale(
                for: localeIdentifier
            )
        else {
            return .unsupported
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .transcription
        )
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .unsupported:
            return .unsupported
        case .supported:
            return .supported
        case .downloading:
            return .downloading
        case .installed:
            return .installed
        @unknown default:
            return .unsupported
        }
    }

    func installAsset(
        for localeIdentifier: String,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard #available(macOS 26.0, *) else {
            throw AppleSpeechServiceError.unavailable
        }
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechServiceError.unavailable
        }
        guard
            let locale = await supportedLocale(
                for: localeIdentifier
            )
        else {
            throw AppleSpeechServiceError.unsupportedLocale
        }

        let reserved: Bool
        do {
            reserved = try await AssetInventory.reserve(locale: locale)
        } catch {
            throw AppleSpeechServiceError.reservationUnavailable
        }
        let existingReservation =
            await AssetInventory.reservedLocales.contains(
                where: { $0.identifier == locale.identifier }
            )
        guard
            reserved || existingReservation
        else {
            throw AppleSpeechServiceError.reservationUnavailable
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .transcription
        )
        if
            await AssetInventory.status(forModules: [transcriber])
                == .installed
        {
            progressHandler(1)
            return
        }

        do {
            guard
                let request =
                    try await AssetInventory
                        .assetInstallationRequest(
                            supporting: [transcriber]
                        )
            else {
                guard
                    await AssetInventory.status(
                        forModules: [transcriber]
                    ) == .installed
                else {
                    throw AppleSpeechServiceError.installationFailed
                }
                progressHandler(1)
                return
            }

            let progress = request.progress
            let monitor = Task {
                while !Task.isCancelled {
                    progressHandler(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            defer {
                monitor.cancel()
            }

            try await request.downloadAndInstall()
            progressHandler(1)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppleSpeechServiceError {
            throw error
        } catch {
            throw AppleSpeechServiceError.installationFailed
        }
    }

    func releaseAssetReservation(
        for localeIdentifier: String
    ) async {
        guard #available(macOS 26.0, *) else {
            return
        }
        guard
            let reservedLocale =
                await AssetInventory.reservedLocales.first(
                    where: { $0.identifier == localeIdentifier }
                )
        else {
            return
        }
        _ = await AssetInventory.release(
            reservedLocale: reservedLocale
        )
    }

    func transcribe(
        fileURL: URL,
        localeIdentifier: String
    ) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AppleSpeechServiceError.unavailable
        }
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechServiceError.unavailable
        }
        guard
            let locale = await supportedLocale(
                for: localeIdentifier
            )
        else {
            throw AppleSpeechServiceError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .transcription
        )
        guard
            await AssetInventory.status(forModules: [transcriber])
                == .installed
        else {
            throw AppleSpeechServiceError.assetMissing
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AppleSpeechServiceError.invalidAudio
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let resultTask = Task { () throws -> String in
            var transcript = ""
            for try await result in transcriber.results {
                try Task.checkCancellation()
                guard result.isFinal else {
                    continue
                }
                transcript.append(
                    String(result.text.characters)
                )
            }
            return transcript
        }

        do {
            let lastSampleTime =
                try await analyzer.analyzeSequence(from: audioFile)
            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(
                    through: lastSampleTime
                )
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await resultTask.value
        } catch is CancellationError {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            if isTransientSpeechError(error) {
                throw AppleSpeechServiceError.temporarilyUnavailable
            }
            throw AppleSpeechServiceError.analysisFailed
        }
    }

    @available(macOS 26.0, *)
    private func isTransientSpeechError(_ error: Error) -> Bool {
        let speechError = error as NSError
        guard speechError.domain == SFSpeechErrorDomain else {
            return false
        }
        let code = SFSpeechError.Code(rawValue: speechError.code)
        return code == .internalServiceError
            || code == .timeout
            || code == .moduleOutputFailed
            || code == .insufficientResources
    }

    @available(macOS 26.0, *)
    private func supportedLocale(
        for identifier: String
    ) async -> Locale? {
        let requested = Locale(identifier: identifier)
        guard
            let equivalent =
                await SpeechTranscriber.supportedLocale(
                    equivalentTo: requested
                ),
            equivalent.language.languageCode
                == requested.language.languageCode
        else {
            return nil
        }
        return equivalent
    }
}
