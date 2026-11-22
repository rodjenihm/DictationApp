import Foundation

nonisolated struct OpenAITranscriptionPayload {
    private let boundary: String
    let body: Data

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    init(model: String, language: String?, audioData: Data) {
        let boundary = "DictationApp-\(UUID().uuidString)"
        self.boundary = boundary

        let isGPTTranscribe =
            model == OpenAIModelCatalog.defaultTranscriptionModelID
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
        if !isGPTTranscribe {
            body.appendMultipartField(
                name: "chunking_strategy",
                value: "auto",
                boundary: boundary
            )
        }
        if let language {
            body.appendMultipartField(
                name: isGPTTranscribe ? "languages[]" : "language",
                value: language,
                boundary: boundary
            )
        }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n"
        )
        body.appendUTF8("Content-Type: audio/mp4\r\n\r\n")
        body.append(audioData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        self.body = body
    }

    static func isValidFieldValue(_ value: String) -> Bool {
        !value.isEmpty && value.rangeOfCharacter(from: .newlines) == nil
    }

    struct Response: Decodable {
        let text: String
    }
}

private extension Data {
    nonisolated mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }

    nonisolated mutating func appendMultipartField(
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
}
