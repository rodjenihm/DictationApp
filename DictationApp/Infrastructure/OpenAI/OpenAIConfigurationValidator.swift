import Foundation

protocol OpenAIConfigurationValidating {
    func validateTranscription(
        credential: String,
        model: String,
        language: LanguageSelection
    ) async throws

    func validatePostProcessing(
        credential: String,
        model: String,
        fastModeEnabled: Bool
    ) async throws
}

enum OpenAIValidationError: LocalizedError {
    case missingValidationFixture
    case invalidRequest
    case invalidCredential
    case modelUnavailable
    case unsupportedLanguage
    case rateLimited
    case providerRejectedConfiguration
    case providerUnavailable
    case malformedResponse
    case transport

    var errorDescription: String? {
        switch self {
        case .missingValidationFixture:
            "The bundled audio validation file is unavailable."
        case .invalidRequest:
            "The validation request could not be created."
        case .invalidCredential:
            "OpenAI rejected the API key."
        case .modelUnavailable:
            "The selected model does not exist or is not accessible with this API key."
        case .unsupportedLanguage:
            "The selected transcription language is not supported."
        case .rateLimited:
            "OpenAI rate-limited the validation request. Check project quota and try again."
        case .providerRejectedConfiguration:
            "OpenAI rejected this model for the selected stage."
        case .providerUnavailable:
            "OpenAI is temporarily unavailable. Try again later."
        case .malformedResponse:
            "OpenAI returned an unexpected validation response."
        case .transport:
            "The validation request could not reach OpenAI. Check the network connection and try again."
        }
    }
}

final class OpenAIConfigurationValidator: OpenAIConfigurationValidating {
    private let session: URLSession
    private let bundle: Bundle
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(bundle: Bundle = .main) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
        self.bundle = bundle
    }

    func validateTranscription(
        credential: String,
        model: String,
        language: LanguageSelection
    ) async throws {
        guard OpenAITranscriptionPayload.isValidFieldValue(model) else {
            throw OpenAIValidationError.invalidRequest
        }
        let languageID = OpenAIModelCatalog.transcriptionLanguageAPIIdentifier(
            for: language
        )
        guard language == .automatic || languageID != nil else {
            throw OpenAIValidationError.unsupportedLanguage
        }
        guard
            let fixtureURL = bundle.url(
                forResource: "silent-validation",
                withExtension: "m4a"
            )
        else {
            throw OpenAIValidationError.missingValidationFixture
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: fixtureURL)
        } catch {
            throw OpenAIValidationError.missingValidationFixture
        }

        let payload = OpenAITranscriptionPayload(
            model: model,
            language: languageID,
            audioData: audioData
        )

        var request = try authorizedRequest(
            path: "audio/transcriptions",
            credential: credential
        )
        request.httpMethod = "POST"
        request.setValue(
            payload.contentType,
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = payload.body

        let data = try await perform(request)
        guard
            (try? decoder.decode(OpenAITranscriptionPayload.Response.self, from: data))
                != nil
        else {
            throw OpenAIValidationError.malformedResponse
        }
    }

    func validatePostProcessing(
        credential: String,
        model: String,
        fastModeEnabled: Bool
    ) async throws {
        var payload = OpenAICleanupPayload(
            model: model,
            instructions:
                "Return only the word OK. Do not add punctuation or explanation.",
            input: "Configuration validation",
            maxOutputTokens: 128,
            fastModeEnabled: fastModeEnabled
        )

        var request = try authorizedRequest(
            path: "responses",
            credential: credential
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let data: Data
        do {
            data = try await performCleanupValidation(request, payload: payload)
        } catch is OpenAIFastTierRejected {
            payload.serviceTier = .standard
            data = try await performCleanupValidation(request, payload: payload)
        }
        guard
            let response = try? decoder.decode(
                ResponsesValidationResponse.self,
                from: data
            ),
            response.status == "completed",
            response.output.contains(where: \.containsOutputText)
        else {
            throw OpenAIValidationError.malformedResponse
        }
    }

    private func performCleanupValidation(
        _ request: URLRequest,
        payload: OpenAICleanupPayload
    ) async throws -> Data {
        try Task.checkCancellation()
        var request = request
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw OpenAIValidationError.invalidRequest
        }
        return try await perform(request, serviceTier: payload.serviceTier)
    }

    private func authorizedRequest(
        path: String,
        credential: String
    ) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/\(path)") else {
            throw OpenAIValidationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Bearer \(credential)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func perform(
        _ request: URLRequest,
        serviceTier: OpenAICleanupPayload.ServiceTier? = nil
    ) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw OpenAIValidationError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIValidationError.malformedResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if
                serviceTier == .fast,
                OpenAIFastTierRejected.matches(
                    tier: serviceTier,
                    statusCode: httpResponse.statusCode,
                    error: try? decoder.decode(
                        OpenAICleanupErrorResponse.self,
                        from: data
                    ).error
                )
            {
                throw OpenAIFastTierRejected()
            }
            throw error(for: httpResponse.statusCode)
        }

        return data
    }

    private func error(for statusCode: Int) -> OpenAIValidationError {
        switch statusCode {
        case 401:
            .invalidCredential
        case 403, 404:
            .modelUnavailable
        case 408, 429:
            .rateLimited
        case 400, 409, 422:
            .providerRejectedConfiguration
        case 500...599:
            .providerUnavailable
        default:
            .providerRejectedConfiguration
        }
    }
}

private struct ResponsesValidationResponse: Decodable {
    let status: String
    let output: [OutputItem]

    struct OutputItem: Decodable {
        let content: [Content]?

        var containsOutputText: Bool {
            content?.contains {
                $0.type == "output_text" && !($0.text ?? "").isEmpty
            } ?? false
        }
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }
}
