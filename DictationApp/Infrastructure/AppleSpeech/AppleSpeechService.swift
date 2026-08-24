import AVFoundation
import Foundation
import OSLog
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
            "Apple Speech is temporarily unavailable. Try again. If the problem persists, quit and reopen DictationApp."
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

        try await ensureAssetReservation(for: locale)

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

        for attempt in 1...2 {
            do {
                try await downloadAsset(
                    supporting: transcriber,
                    progressHandler: progressHandler
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AppleSpeechServiceError {
                throw error
            } catch {
                logFrameworkFailure(
                    error,
                    operation: "asset installation"
                )
                guard isXPCConnectionFailure(error) else {
                    throw AppleSpeechServiceError.installationFailed
                }
                guard attempt == 1 else {
                    throw AppleSpeechServiceError.temporarilyUnavailable
                }
                AppLog.providers.notice(
                    "Apple Speech service connection failed; retrying asset installation"
                )
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func releaseAssetReservation(
        for localeIdentifier: String
    ) async {
        guard #available(macOS 26.0, *) else {
            return
        }
        let requestedLocale = Locale(identifier: localeIdentifier)
        guard
            let reservedLocale = await AssetInventory.reservedLocales.first(
                where: { assetLocale($0, matches: requestedLocale) }
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
    private func ensureAssetReservation(
        for locale: Locale
    ) async throws {
        for attempt in 1...2 {
            try Task.checkCancellation()

            let existingReservations = await AssetInventory.reservedLocales
            if existingReservations.contains(
                where: { assetLocale($0, matches: locale) }
            ) {
                return
            }
            if
                existingReservations.count
                    >= AssetInventory.maximumReservedLocales
            {
                AppLog.providers.notice(
                    "Apple Speech asset reservation capacity reached"
                )
                throw AppleSpeechServiceError.reservationUnavailable
            }

            do {
                if try await AssetInventory.reserve(locale: locale) {
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logFrameworkFailure(
                    error,
                    operation: "asset reservation"
                )
                let updatedReservations =
                    await AssetInventory.reservedLocales
                if updatedReservations.contains(
                    where: { assetLocale($0, matches: locale) }
                ) {
                    return
                }
                if
                    updatedReservations.count
                        >= AssetInventory.maximumReservedLocales
                {
                    throw AppleSpeechServiceError.reservationUnavailable
                }
                guard attempt == 1 else {
                    throw AppleSpeechServiceError.temporarilyUnavailable
                }
                AppLog.providers.notice(
                    "Apple Speech service failed to reserve an asset; retrying"
                )
                try await Task.sleep(for: .milliseconds(500))
                continue
            }

            let updatedReservations = await AssetInventory.reservedLocales
            if updatedReservations.contains(
                where: { assetLocale($0, matches: locale) }
            ) {
                return
            }
            guard attempt == 1 else {
                throw AppleSpeechServiceError.temporarilyUnavailable
            }
            AppLog.providers.notice(
                "Apple Speech returned no asset reservation; retrying"
            )
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    @available(macOS 26.0, *)
    private func downloadAsset(
        supporting transcriber: SpeechTranscriber,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard
            let request =
                try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                )
        else {
            guard
                await AssetInventory.status(forModules: [transcriber])
                    == .installed
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
    }

    private func assetLocale(
        _ locale: Locale,
        matches requestedLocale: Locale
    ) -> Bool {
        locale.language.languageCode
            == requestedLocale.language.languageCode
            && locale.language.script
                == requestedLocale.language.script
            && locale.region == requestedLocale.region
    }

    private func isXPCConnectionFailure(_ error: Error) -> Bool {
        errorChain(error).contains { error in
            guard error.domain == NSCocoaErrorDomain else {
                return false
            }
            return error.code == NSXPCConnectionInterrupted
                || error.code == NSXPCConnectionInvalid
                || error.code == NSXPCConnectionReplyInvalid
        }
    }

    private func logFrameworkFailure(
        _ error: Error,
        operation: String
    ) {
        for (depth, frameworkError) in errorChain(error).enumerated() {
            AppLog.providers.error(
                "Apple Speech \(operation, privacy: .public) failure \(depth, privacy: .public): domain=\(frameworkError.domain, privacy: .public) code=\(frameworkError.code, privacy: .public)"
            )
        }
    }

    private func errorChain(_ error: Error) -> [NSError] {
        var result: [NSError] = []
        var current: NSError? = error as NSError

        while let frameworkError = current, result.count < 3 {
            result.append(frameworkError)
            current = frameworkError.userInfo[NSUnderlyingErrorKey]
                as? NSError
        }
        return result
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
