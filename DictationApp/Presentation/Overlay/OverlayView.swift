import SwiftUI

struct OverlayView: View {
    let state: OverlayViewState
    let onStop: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void
    let onTranscribePartial: () -> Void
    let onRepairTranscription: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        presentationContent
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var presentationContent: some View {
        if usesAttentionPresentation {
            attentionContent
        } else {
            compactContent
        }
    }

    private var compactContent: some View {
        HStack(spacing: 8) {
            stateIndicator

            Text(compactTitle)
                .font(
                    .system(
                        .callout,
                        design: .rounded,
                        weight: .semibold
                    )
                )
                .foregroundStyle(compactTitleColor)
                .lineLimit(1)
                .truncationMode(.middle)

            compactControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var attentionContent: some View {
        HStack(spacing: 12) {
            stateIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(
                        .system(
                            .body,
                            design: .rounded,
                            weight: .semibold
                        )
                    )
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            attentionControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            minWidth: 440,
            idealWidth: attentionIdealWidth,
            maxWidth: 520
        )
    }

    @ViewBuilder
    private var compactControls: some View {
        switch state {
        case .recording:
            compactStopButton
            compactCancelButton
        case
            .preparing,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .tooShort:
            compactCancelButton
        case
            .inserted,
            .rawTranscriptFallback,
            .noSpeech,
            .cancelled,
            .insertionUnverified,
            .clipboardFallback,
            .transcriptionFailed,
            .captureFailed,
            .failed:
            EmptyView()
        }
    }

    private var compactStopButton: some View {
        Button(action: onStop) {
            Label("Stop dictation", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .tint(.red)
        .focusable(false)
        .accessibilityLabel("Stop dictation")
        .help("Stop dictation")
    }

    private var compactCancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Label("Cancel dictation", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .focusable(false)
        .accessibilityLabel("Cancel dictation")
        .help("Cancel dictation")
    }

    @ViewBuilder
    private var attentionControls: some View {
        switch state {
        case .transcriptionFailed(_, let canRepair):
            if canRepair {
                Button(
                    "Settings",
                    action: onRepairTranscription
                )
                .buttonStyle(.bordered)
                .focusable(false)
            }

            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .focusable(false)

            Button(
                "Discard",
                role: .destructive,
                action: onDiscard
            )
            .buttonStyle(.bordered)
            .focusable(false)
        case .captureFailed:
            Button(
                "Transcribe Partial",
                action: onTranscribePartial
            )
            .buttonStyle(.borderedProminent)
            .focusable(false)

            Button(
                "Discard",
                role: .destructive,
                action: onCancel
            )
            .buttonStyle(.bordered)
            .focusable(false)
        case
            .insertionUnverified,
            .clipboardFallback:
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.bordered)
                .focusable(false)
        case .failed:
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .focusable(false)
        case
            .preparing,
            .recording,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .inserted,
            .rawTranscriptFallback,
            .noSpeech,
            .tooShort,
            .cancelled:
            EmptyView()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.45), radius: 2)
                .accessibilityLabel("Recording")
        case .completed, .inserted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
                .accessibilityHidden(true)
        case
            .rawTranscriptFallback,
            .insertionUnverified,
            .clipboardFallback:
            Image(systemName: "text.badge.exclamationmark")
                .foregroundStyle(.orange)
                .font(.body)
                .accessibilityHidden(true)
        case .noSpeech:
            Image(systemName: "waveform.slash")
                .foregroundStyle(.secondary)
                .font(.body)
                .accessibilityHidden(true)
        case
            .tooShort,
            .failed,
            .transcriptionFailed,
            .captureFailed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.body)
                .accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.body)
                .accessibilityHidden(true)
        case
            .preparing,
            .finalizing,
            .transcribing,
            .postProcessing,
            .inserting:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Working")
        }
    }

    private var usesAttentionPresentation: Bool {
        switch state {
        case
            .insertionUnverified,
            .clipboardFallback,
            .transcriptionFailed,
            .captureFailed,
            .failed:
            true
        case
            .preparing,
            .recording,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .inserted,
            .rawTranscriptFallback,
            .noSpeech,
            .tooShort,
            .cancelled:
            false
        }
    }

    private var compactTitle: String {
        switch state {
        case .preparing:
            "Starting…"
        case .recording(
            let elapsed,
            let inputDeviceName,
            let isUsingFallback,
            let isNearDurationLimit
        ):
            compactRecordingTitle(
                elapsed: elapsed,
                inputDeviceName: inputDeviceName,
                isUsingFallback: isUsingFallback,
                isNearDurationLimit: isNearDurationLimit
            )
        case .finalizing(let reason):
            switch reason {
            case .stopped:
                "Finalizing…"
            case .automaticLimit:
                "Limit reached · Finalizing…"
            case .cancelled:
                "Cancelling…"
            }
        case .completed(let duration):
            "Captured locally · \(formatDuration(duration))"
        case .transcribing:
            "Transcribing…"
        case .postProcessing:
            "Cleaning up…"
        case .inserting:
            "Inserting…"
        case .inserted:
            "Transcript inserted"
        case .rawTranscriptFallback:
            "Cleanup unavailable · Raw text inserted"
        case .noSpeech:
            "No speech detected"
        case .tooShort:
            "Recording too short"
        case .cancelled:
            "Recording cancelled"
        case
            .insertionUnverified,
            .clipboardFallback,
            .transcriptionFailed,
            .captureFailed,
            .failed:
            title
        }
    }

    private var compactTitleColor: Color {
        switch state {
        case
            .rawTranscriptFallback,
            .tooShort:
            .orange
        case .recording(
            _,
            _,
            let isUsingFallback,
            let isNearDurationLimit
        ):
            isUsingFallback || isNearDurationLimit ? .orange : .primary
        case .noSpeech, .cancelled:
            .secondary
        default:
            .primary
        }
    }

    private var title: String {
        switch state {
        case .preparing:
            "Activating microphone…"
        case .recording(let elapsed, _, _, _):
            "Recording \(formatDuration(elapsed))"
        case .finalizing(let reason):
            switch reason {
            case .stopped:
                "Finalizing recording…"
            case .automaticLimit:
                "Maximum duration reached"
            case .cancelled:
                "Cancelling recording…"
            }
        case .completed(let duration):
            "Captured locally (\(formatDuration(duration)))"
        case .transcribing:
            "Transcribing recording…"
        case .postProcessing:
            "Cleaning up transcript…"
        case .inserting:
            "Inserting transcript…"
        case .inserted:
            "Transcript inserted"
        case .insertionUnverified:
            "Transcript remains available"
        case .clipboardFallback:
            "Paste transcript manually"
        case .rawTranscriptFallback:
            "Raw transcript inserted"
        case .noSpeech:
            "No speech detected"
        case .transcriptionFailed:
            "Transcription failed"
        case .captureFailed(_, let duration):
            "Partial recording (\(formatDuration(duration)))"
        case .tooShort:
            "Recording too short"
        case .cancelled:
            "Recording cancelled"
        case .failed:
            "Recording failed"
        }
    }

    private var detail: String? {
        switch state {
        case .insertionUnverified(let message):
            message
        case .clipboardFallback(let message):
            message
        case .transcriptionFailed(let message, _):
            message
        case .captureFailed(let message, _):
            message
        case .failed(let message):
            message
        case
            .preparing,
            .recording,
            .finalizing,
            .completed,
            .transcribing,
            .postProcessing,
            .inserting,
            .inserted,
            .rawTranscriptFallback,
            .noSpeech,
            .tooShort,
            .cancelled:
            nil
        }
    }

    private var detailColor: Color {
        switch state {
        case
            .insertionUnverified,
            .clipboardFallback,
            .transcriptionFailed,
            .captureFailed,
            .failed:
            .orange
        default:
            .secondary
        }
    }

    private var attentionIdealWidth: CGFloat {
        switch state {
        case .transcriptionFailed(_, true), .captureFailed:
            520
        case
            .transcriptionFailed,
            .insertionUnverified,
            .clipboardFallback:
            480
        default:
            440
        }
    }

    private func compactRecordingTitle(
        elapsed: TimeInterval,
        inputDeviceName: String,
        isUsingFallback: Bool,
        isNearDurationLimit: Bool
    ) -> String {
        var components = ["Recording \(formatDuration(elapsed))"]
        if isUsingFallback {
            components.append("\(inputDeviceName) fallback")
        }
        if isNearDurationLimit {
            components.append("Limit soon")
        }
        return components.joined(separator: " · ")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}
