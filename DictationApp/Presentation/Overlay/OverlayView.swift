import SwiftUI

struct OverlayView: View {
    let state: OverlayViewState
    let onStop: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            stateIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .recording = state {
                Button("Stop", action: onStop)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .focusable(false)
            }

            switch state {
            case .transcriptionFailed:
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
            case .transcribedToClipboard, .noSpeech:
                EmptyView()
            default:
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .focusable(false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 500)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.24), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .shadow(color: .red.opacity(0.6), radius: 4)
                .accessibilityLabel("Recording")
        case .completed, .transcribedToClipboard:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
                .accessibilityHidden(true)
        case .noSpeech:
            Image(systemName: "waveform.slash")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)
        case .tooShort, .failed, .transcriptionFailed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)
        case .preparing, .finalizing, .transcribing:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Working")
        }
    }

    private var title: String {
        switch state {
        case .preparing:
            "Preparing recording…"
        case .recording(let elapsed, _, _):
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
        case .transcribedToClipboard:
            "Transcript copied"
        case .noSpeech:
            "No speech detected"
        case .transcriptionFailed:
            "Transcription failed"
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
        case .recording(_, let inputDeviceName, let isNearDurationLimit):
            isNearDurationLimit
                ? "\(inputDeviceName) — recording limit soon"
                : inputDeviceName
        case .finalizing(.automaticLimit):
            "Finalizing the captured audio"
        case .completed:
            "The local recording will be discarded"
        case .transcribing(let providerName):
            "Uploading completed audio to \(providerName)"
        case .transcribedToClipboard:
            "Paste the transcript manually"
        case .noSpeech:
            "The clipboard was left unchanged"
        case .transcriptionFailed(let message):
            message
        case .tooShort:
            "Record for at least half a second"
        case .failed(let message):
            message
        case .preparing, .finalizing, .cancelled:
            nil
        }
    }

    private var detailColor: Color {
        switch state {
        case
            .recording(_, _, true),
            .tooShort,
            .failed,
            .transcriptionFailed:
            .orange
        default:
            .secondary
        }
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
