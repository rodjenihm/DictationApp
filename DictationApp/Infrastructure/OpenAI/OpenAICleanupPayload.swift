import Foundation

struct OpenAICleanupPayload: Encodable {
    enum ServiceTier: String, Encodable {
        case fast
        case standard = "default"
    }

    private struct Reasoning: Encodable {
        let effort: String
    }

    private struct Tool: Encodable {}

    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    var serviceTier: ServiceTier?

    private let reasoning: Reasoning
    private let tools: [Tool] = []
    private let store = false

    init(
        model: String,
        instructions: String,
        input: String,
        maxOutputTokens: Int,
        fastModeEnabled: Bool
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.maxOutputTokens = maxOutputTokens
        serviceTier = if OpenAIModelCatalog.supportsPostProcessingFastMode(for: model) {
            fastModeEnabled ? .fast : .standard
        } else {
            nil
        }
        reasoning = Reasoning(
            effort: OpenAIModelCatalog.postProcessingReasoningEffort(for: model)
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case serviceTier = "service_tier"
        case reasoning
        case tools
        case store
    }
}

struct OpenAIFastTierRejected: Error {
    static func matches(
        tier: OpenAICleanupPayload.ServiceTier?,
        statusCode: Int,
        error: OpenAICleanupErrorResponse.ProviderError?
    ) -> Bool {
        tier == .fast
            && statusCode == 400
            && error?.type == "invalid_request_error"
            && error?.param == "service_tier"
    }
}

struct OpenAICleanupErrorResponse: Decodable {
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
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            code = try? container.decodeIfPresent(String.self, forKey: .code)
            param = try container.decodeIfPresent(String.self, forKey: .param)
        }
    }
}
