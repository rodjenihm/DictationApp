import Foundation

final class OpenAITranscriptionProvider: TranscriptionProvider {
    let providerID = ProviderID.openAI

    private static let maximumUploadBytes = 25 * 1_024 * 1_024

    private let credentialStore: any CredentialStore
    private let session: URLSession
    private let baseURL: URL
    private let retryExecutor: RetryExecutor
    private let decoder = JSONDecoder()

    init(
        credentialStore: any CredentialStore,
        session: URLSession? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1/")!,
        retryExecutor: RetryExecutor = RetryExecutor()
    ) {
        self.credentialStore = credentialStore
        self.baseURL = baseURL
        self.retryExecutor = retryExecutor

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: configuration)
        }
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> String {
        try Task.checkCancellation()

        let model = try modelIdentifier(for: request.model)
        let language = try languageIdentifier(for: request.language)
        let audioData = try loadAudioData(from: request.artifact)
        let credential = try resolveCredential()

        return try await retryExecutor.execute { [self] in
            try Task.checkCancellation()
            let urlRequest = try makeRequest(
                credential: credential,
                model: model,
                language: language,
                audioData: audioData
            )
            return try await perform(urlRequest)
        }
    }

    private func modelIdentifier(
        for selection: ModelSelection
    ) throws -> String {
        guard
            let identifier =
                OpenAIModelCatalog.transcriptionAPIIdentifier(for: selection),
            isSafeMultipartValue(identifier)
        else {
            throw ProviderOperationFailure.scopedConfiguration(
                kind: .model,
                message: "The transcription model is not configured correctly."
            )
        }
        return identifier
    }

    private func languageIdentifier(
        for selection: LanguageSelection
    ) throws -> String? {
        switch selection {
        case .automatic:
            return nil
        case .explicit:
            guard
                let identifier =
                    OpenAIModelCatalog
                        .transcriptionLanguageAPIIdentifier(for: selection),
                isSafeMultipartValue(identifier)
            else {
                throw ProviderOperationFailure.scopedConfiguration(
                    kind: .language,
                    message: "The transcription language is not supported."
                )
            }
            return identifier
        }
    }

    private func resolveCredential() throws -> String {
        let credential: String

        do {
            guard let savedCredential = try credentialStore.readCredential()
            else {
                throw ProviderOperationFailure.scopedConfiguration(
                    kind: .authentication,
                    message: "The OpenAI API key is missing."
                )
            }
            credential = savedCredential
        } catch let failure as ProviderOperationFailure {
            throw failure
        } catch {
            throw ProviderOperationFailure.scopedConfiguration(
                kind: .providerSetup,
                message: "The OpenAI API key could not be read from Keychain."
            )
        }

        guard !credential.isEmpty else {
            throw ProviderOperationFailure.scopedConfiguration(
                kind: .authentication,
                message: "The OpenAI API key is missing."
            )
        }
        return credential
    }

    private func loadAudioData(
        from artifact: AudioArtifact
    ) throws -> Data {
        guard
            artifact.url.pathExtension.lowercased() == "m4a",
            artifact.fileSize > 0,
            artifact.fileSize < Self.maximumUploadBytes,
            FileManager.default.isReadableFile(
                atPath: artifact.url.path
            )
        else {
            throw invalidAudioFailure(for: artifact)
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: artifact.url)
        } catch {
            throw ProviderOperationFailure.operation(
                message: "The finalized recording could not be read."
            )
        }

        guard
            !audioData.isEmpty,
            audioData.count < Self.maximumUploadBytes
        else {
            throw invalidAudioFailure(for: artifact)
        }
        return audioData
    }

    private func invalidAudioFailure(
        for artifact: AudioArtifact
    ) -> ProviderOperationFailure {
        if artifact.fileSize >= Self.maximumUploadBytes {
            return .operation(
                message:
                    "The recording exceeds OpenAI’s 25 MB upload limit."
            )
        }
        return .operation(
            message: "The finalized recording is not a readable M4A file."
        )
    }

    private func makeRequest(
        credential: String,
        model: String,
        language: String?,
        audioData: Data
    ) throws -> URLRequest {
        guard
            let url = URL(
                string: "audio/transcriptions",
                relativeTo: baseURL
            )
        else {
            throw ProviderOperationFailure.operation(
                message: "The transcription request could not be created."
            )
        }

        let boundary = "DictationApp-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(
            name: "model",
            value: model,
            boundary: boundary
        )
        body.appendMultipartField(
            name: "response_format",
            value: "json",
            boundary: boundary
        )
        body.appendMultipartField(
            name: "chunking_strategy",
            value: "auto",
            boundary: boundary
        )
        if let language {
            body.appendMultipartField(
                name: "language",
                value: language,
                boundary: boundary
            )
        }
        body.appendMultipartFile(
            name: "file",
            filename: "recording.m4a",
            contentType: "audio/mp4",
            data: audioData,
            boundary: boundary
        )
        body.appendUTF8("--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            "Bearer \(credential)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return request
    }

    private func perform(_ request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw ProviderOperationFailure.cancelled
        } catch let error as URLError {
            if error.code == .cancelled {
                throw ProviderOperationFailure.cancelled
            }
            throw ProviderOperationFailure.transient(
                message:
                    "OpenAI could not be reached. Check the network connection and retry.",
                retryAfter: nil
            )
        } catch {
            throw ProviderOperationFailure.transient(
                message:
                    "OpenAI could not be reached. Check the network connection and retry.",
                retryAfter: nil
            )
        }

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderOperationFailure.operation(
                message: "OpenAI returned an unexpected response."
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw failure(for: httpResponse, data: data)
        }

        guard
            let response = try? decoder.decode(
                TranscriptionResponse.self,
                from: data
            )
        else {
            throw ProviderOperationFailure.operation(
                message: "OpenAI returned an unexpected transcription response."
            )
        }

        return response.text
    }

    private func failure(
        for response: HTTPURLResponse,
        data: Data
    ) -> ProviderOperationFailure {
        let providerError = try? decoder.decode(
            OpenAIErrorResponse.self,
            from: data
        ).error
        let code = providerError?.code?.lowercased()
        let type = providerError?.type?.lowercased()
        let parameter = providerError?.param?.lowercased()

        if
            code == "insufficient_quota"
                || type == "insufficient_quota"
                || code == "billing_hard_limit_reached"
        {
            return .operation(
                message:
                    "OpenAI quota is unavailable. Check project billing or quota before retrying."
            )
        }

        switch response.statusCode {
        case 401:
            return .scopedConfiguration(
                kind: .authentication,
                message: "OpenAI rejected the saved API key."
            )
        case 403, 404:
            return .scopedConfiguration(
                kind: .model,
                message:
                    "The selected transcription model is unavailable for this API key."
            )
        case 408, 429:
            return .transient(
                message:
                    "OpenAI temporarily could not complete the transcription.",
                retryAfter: retryAfter(from: response)
            )
        case 500...599:
            return .transient(
                message: "OpenAI is temporarily unavailable.",
                retryAfter: retryAfter(from: response)
            )
        case 400, 409, 422:
            if
                Self.configurationErrorCodes.contains(code ?? "")
                    || type == "invalid_api_key"
                    || (
                        type == "invalid_request_error"
                            && parameter == "model"
                    )
            {
                let kind: ProviderConfigurationIssueKind =
                    type == "invalid_api_key"
                    ? .authentication
                    : .model
                return .scopedConfiguration(
                    kind: kind,
                    message:
                        "OpenAI rejected the saved transcription configuration."
                )
            }
            return .operation(
                message: "OpenAI rejected the transcription request."
            )
        default:
            return .operation(
                message: "OpenAI rejected the transcription request."
            )
        }
    }

    private func retryAfter(
        from response: HTTPURLResponse
    ) -> TimeInterval? {
        guard
            let value = response.value(
                forHTTPHeaderField: "Retry-After"
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }

        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss z",
            "EEEE',' dd-MMM-yy HH':'mm':'ss z",
            "EEE MMM d HH':'mm':'ss yyyy",
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return max(0, date.timeIntervalSinceNow)
            }
        }

        return nil
    }

    private func isSafeMultipartValue(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("\r")
            && !value.contains("\n")
    }

    private static let configurationErrorCodes: Set<String> = [
        "invalid_api_key",
        "invalid_model",
        "model_not_available",
        "model_not_found",
        "model_not_supported",
        "unsupported_model",
    ]
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct OpenAIErrorResponse: Decodable {
    let error: ProviderError

    struct ProviderError: Decodable {
        let type: String?
        let code: String?
        let param: String?

        enum CodingKeys: String, CodingKey {
            case type
            case code
            case param
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            type = try container.decodeIfPresent(
                String.self,
                forKey: .type
            )

            if
                let stringCode = try? container.decodeIfPresent(
                    String.self,
                    forKey: .code
                )
            {
                code = stringCode
            } else {
                code = nil
            }

            param = try container.decodeIfPresent(
                String.self,
                forKey: .param
            )
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(
        name: String,
        value: String,
        boundary: String
    ) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        )
        appendUTF8("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; " +
                "filename=\"\(filename)\"\r\n"
        )
        appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendUTF8("\r\n")
    }
}
