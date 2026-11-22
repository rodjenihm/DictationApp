import Foundation

enum PostProcessingOutputPolicyError: String, Error, Sendable {
    case empty
    case excessiveExpansion = "excessive_expansion"
    case codeFence = "code_fence"
    case enclosingQuotes = "enclosing_quotes"
    case markdownHeading = "markdown_heading"
    case preamble
}

enum PostProcessingOutputPolicy {
    private nonisolated static let quotationPairs: [(Character, Character)] = [
        ("\"", "\""), ("“", "”"), ("‘", "’"), ("'", "'"),
    ]
    private nonisolated static let quotationMarks = Set(
        quotationPairs.flatMap { [$0.0, $0.1] }
    )

    static func maximumCharacterCount(
        for rawTranscript: String
    ) -> Int {
        let rawCount = rawTranscript.count
        return max(
            rawCount + 256,
            Int(ceil(Double(rawCount) * 1.5))
        )
    }

    static func maximumOutputTokens(
        for rawTranscript: String
    ) -> Int {
        let characterBound =
            maximumCharacterCount(for: rawTranscript)
        // Responses counts reasoning tokens against this budget. The
        // character policy below remains the hard visible-output bound.
        return min(
            4_096,
            max(64, characterBound * 4)
        )
    }

    static func validatedOutput(
        _ output: String,
        rawTranscript: String
    ) throws -> String {
        let normalized = output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !normalized.isEmpty else {
            throw PostProcessingOutputPolicyError.empty
        }

        guard
            normalized.count
                <= maximumCharacterCount(for: rawTranscript)
        else {
            throw PostProcessingOutputPolicyError.excessiveExpansion
        }

        guard !introducesCodeFence(normalized, comparedWith: rawTranscript) else {
            throw PostProcessingOutputPolicyError.codeFence
        }
        guard !hasEnclosingQuotes(normalized) else {
            throw PostProcessingOutputPolicyError.enclosingQuotes
        }
        guard !introducesMarkdownHeading(normalized, comparedWith: rawTranscript) else {
            throw PostProcessingOutputPolicyError.markdownHeading
        }
        guard !introducesPreamble(normalized, comparedWith: rawTranscript) else {
            throw PostProcessingOutputPolicyError.preamble
        }

        return normalized
    }

    nonisolated static func removingPresentationQuotes(
        from output: String,
        rawTranscript: String
    ) -> String {
        let edited = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let first = raw.first,
            let last = raw.last,
            !quotationMarks.contains(first),
            !quotationMarks.contains(last),
            hasEnclosingQuotes(edited)
        else {
            return edited
        }
        let decoded = try? JSONDecoder().decode(String.self, from: Data(edited.utf8))
        let unwrapped = decoded ?? String(edited.dropFirst().dropLast())
        return unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func introducesCodeFence(
        _ output: String,
        comparedWith rawTranscript: String
    ) -> Bool {
        codeFenceCount(in: output)
            > codeFenceCount(in: rawTranscript)
    }

    private static func codeFenceCount(in text: String) -> Int {
        ["```", "~~~"].reduce(into: 0) { count, marker in
            count += text.components(separatedBy: marker).count - 1
        }
    }

    private nonisolated static func hasEnclosingQuotes(_ text: String) -> Bool {
        guard
            let first = text.first,
            let last = text.last,
            text.count > 1
        else {
            return false
        }

        return quotationPairs.contains { opening, closing in
            first == opening && last == closing
        }
    }

    private static func introducesMarkdownHeading(
        _ output: String,
        comparedWith rawTranscript: String
    ) -> Bool {
        markdownHeadingCount(in: output)
            > markdownHeadingCount(in: rawTranscript)
    }

    private static func introducesPreamble(
        _ output: String,
        comparedWith rawTranscript: String
    ) -> Bool {
        let outputLowercased = output.lowercased()
        let rawLowercased = rawTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let preambles = [
            "here is the cleaned transcript",
            "here's the cleaned transcript",
            "here is the cleaned text",
            "here's the cleaned text",
            "sure, here is the cleaned transcript",
            "sure, here's the cleaned transcript",
            "certainly, here is the cleaned transcript",
            "certainly, here's the cleaned transcript",
            "cleaned transcript:",
            "cleaned-up transcript:",
            "cleaned text:",
            "transcript:",
            "output:",
        ]

        return preambles.contains {
            outputLowercased.hasPrefix($0)
                && !rawLowercased.hasPrefix($0)
        }
    }

    private static func markdownHeadingCount(
        in text: String
    ) -> Int {
        text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        .reduce(into: 0) { count, line in
            if isMarkdownHeading(line) {
                count += 1
            }
        }
    }

    private static func isMarkdownHeading(
        _ line: Substring
    ) -> Bool {
        let trimmed = line.drop {
            $0 == " " || $0 == "\t"
        }
        let markerCount = trimmed.prefix {
            $0 == "#"
        }
        .count

        guard (1...6).contains(markerCount) else {
            return false
        }

        let remainder = trimmed.dropFirst(markerCount)
        return remainder.first == " " || remainder.first == "\t"
    }
}
