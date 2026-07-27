import Foundation

enum TextInsertionOutcome: Equatable, Sendable {
    case confirmed
    case unverified
    case failed
}

@MainActor
protocol TextInsertionServicing {
    func insert(
        _ text: String,
        using clipboardTransaction: any ClipboardTransactionHandling
    ) async -> TextInsertionOutcome
}

enum TextInsertionBoundaryPolicy {
    static func preparedText(
        _ transcript: String,
        targetValue: String?,
        selectedRange: NSRange?
    ) -> String {
        guard
            let targetValue,
            let selectedRange,
            isValid(selectedRange, in: targetValue)
        else {
            return transcript
        }

        if targetValue.isEmpty
            || (selectedRange.location == 0 && selectedRange.length == 0)
        {
            return transcript
        }

        guard
            let swiftRange = Range(selectedRange, in: targetValue)
        else {
            return transcript
        }

        var result = transcript

        if
            swiftRange.lowerBound > targetValue.startIndex,
            let firstTranscriptCharacter = transcript.first
        {
            let precedingIndex = targetValue.index(
                before: swiftRange.lowerBound
            )
            let precedingCharacter = targetValue[precedingIndex]

            if
                isWordForming(precedingCharacter),
                isWordForming(firstTranscriptCharacter)
            {
                result = " " + result
            }
        }

        if
            swiftRange.upperBound < targetValue.endIndex,
            let lastTranscriptCharacter = transcript.last
        {
            let followingCharacter = targetValue[swiftRange.upperBound]

            if
                isWordForming(lastTranscriptCharacter),
                isWordForming(followingCharacter)
            {
                result += " "
            }
        }

        return result
    }

    static func expectedValue(
        replacing selectedRange: NSRange?,
        in targetValue: String?,
        with insertedText: String
    ) -> String? {
        guard
            let targetValue,
            let selectedRange,
            isValid(selectedRange, in: targetValue)
        else {
            return nil
        }

        return (targetValue as NSString).replacingCharacters(
            in: selectedRange,
            with: insertedText
        )
    }

    private static func isValid(
        _ range: NSRange,
        in value: String
    ) -> Bool {
        range.location != NSNotFound
            && range.location <= value.utf16.count
            && range.length <= value.utf16.count - range.location
    }

    private static func isWordForming(
        _ character: Character
    ) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case
                .uppercaseLetter,
                .lowercaseLetter,
                .titlecaseLetter,
                .modifierLetter,
                .otherLetter,
                .nonspacingMark,
                .spacingMark,
                .enclosingMark,
                .decimalNumber,
                .connectorPunctuation:
                true
            default:
                false
            }
        }
    }
}
