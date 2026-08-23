import SwiftUI

struct ConfigurationView: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        VStack(spacing: 0) {
            ConfigurationAccessBanner(viewModel: viewModel)

            NavigationSplitView {
                ConfigurationSidebar(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(
                        min: 170,
                        ideal: 184,
                        max: 210
                    )
            } detail: {
                ConfigurationDetail(viewModel: viewModel)
            }

            Divider()
            ConfigurationFooter(viewModel: viewModel)
        }
        .frame(minWidth: 720, minHeight: 540)
    }
}

private struct ConfigurationAccessBanner: View {
    let viewModel: ConfigurationViewModel

    var body: some View {
        if let presentation {
            Label(presentation.message, systemImage: presentation.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.35))
                .overlay(alignment: .bottom) {
                    Divider()
                }
        }
    }

    private var presentation: (message: String, systemImage: String)? {
        if let explanation = viewModel.sessionAccessExplanation {
            return (explanation, "lock.fill")
        }
        if viewModel.presentationMode == .transcriptionRepair {
            return (
                "Repair only the transcription provider or model. The retained recording is not uploaded until Retry.",
                "wrench.and.screwdriver.fill"
            )
        }
        return nil
    }
}

private struct ConfigurationSidebar: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        List(
            SettingsDestination.allCases,
            selection: $viewModel.selectedDestination
        ) { destination in
            HStack(spacing: 10) {
                Label(
                    destination.title,
                    systemImage: destination.systemImage
                )

                Spacer()

                if viewModel.hasIssue(in: destination) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Contains an error")
                } else if viewModel.isDirty(destination) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Contains unsaved changes")
                } else if hasAttention(destination) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs attention")
                }
            }
            .tag(destination)
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Settings categories")
    }

    private func hasAttention(
        _ destination: SettingsDestination
    ) -> Bool {
        switch destination {
        case .providers:
            return viewModel.providerRegistry.settingsModules.contains {
                let state = viewModel.providerReadiness($0.id).state
                return state == .attentionRequired
                    || state == .setupRequired
            }
        case .transcription:
            let state = viewModel.providerReadiness(
                viewModel.transcriptionProviderChoice
            ).state
            return state == .attentionRequired
                || state == .setupRequired
        case .postProcessing:
            return viewModel.postProcessingAttentionMessage != nil
        case .general:
            return false
        }
    }
}

private struct ConfigurationDetail: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        switch viewModel.selectedDestination {
        case .general:
            ConfigurationGeneralView(viewModel: viewModel)
                .disabled(
                    !canEdit(.general) || viewModel.isValidating
                )
        case .transcription:
            ConfigurationTranscriptionView(viewModel: viewModel)
                .disabled(
                    !canEdit(.transcription) || viewModel.isValidating
                )
        case .postProcessing:
            ConfigurationPostProcessingView(viewModel: viewModel)
                .disabled(
                    !canEdit(.postProcessing)
                        || viewModel.isValidating
                )
        case .providers:
            ConfigurationProvidersView(viewModel: viewModel)
                .disabled(
                    !canEdit(.providers) || viewModel.isValidating
                )
        }
    }

    private func canEdit(_ destination: SettingsDestination) -> Bool {
        guard viewModel.canEditPresentedSettings else {
            return false
        }
        if viewModel.presentationMode == .transcriptionRepair {
            return destination == .transcription
                || destination == .providers
        }
        return true
    }
}

private struct ConfigurationFooter: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        HStack(spacing: 12) {
            if let issue = viewModel.issues.first {
                ConfigurationStatusLabel(
                    title: issue.message,
                    systemImage: "exclamationmark.circle.fill",
                    style: .error
                )
                .lineLimit(2)
            } else if let success = viewModel.successMessage {
                ConfigurationStatusLabel(
                    title: success,
                    systemImage: "checkmark.circle.fill",
                    style: .success
                )
            } else {
                ConfigurationStatusLabel(
                    title: footerDetail,
                    systemImage: "lock.shield",
                    style: .neutral
                )
            }

            Spacer(minLength: 8)

            if viewModel.isValidating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Validating configuration")
                Button("Cancel") {
                    viewModel.cancelValidation()
                }
            } else {
                AccessibleActionButton(
                    title: viewModel.saveButtonTitle,
                    accessibilityLabel: viewModel.saveButtonTitle,
                    accessibilityHelp:
                        "Validates and saves all Settings changes.",
                    isDefault: true
                ) {
                    Task {
                        _ = await viewModel.save()
                    }
                }
                .fixedSize()
                .disabled(!viewModel.canSave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var footerDetail: String {
        switch viewModel.presentationMode {
        case .full:
            "Changes apply together after validation."
        case .transcriptionRepair:
            "Retry remains a separate explicit action."
        }
    }
}
