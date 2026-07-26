import SwiftUI

struct ConfigurationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up DictationApp")
                        .font(.title2.weight(.semibold))

                    Text("Configuration is required before dictation can start.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "OpenAI transcription provider",
                    systemImage: "cloud"
                )
                Label(
                    "Microphone and Accessibility permissions",
                    systemImage: "lock.shield"
                )
                Label(
                    "Global dictation shortcut",
                    systemImage: "keyboard"
                )
            }
            .foregroundStyle(.secondary)

            Text(
                "Provider, permission, and shortcut controls will be added " +
                "in the next implementation slices."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()

            Text(
                "You can close this window. DictationApp will continue " +
                "running in the menu bar."
            )
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 330)
    }
}

#Preview {
    ConfigurationView()
}
