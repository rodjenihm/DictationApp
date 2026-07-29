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
                        ideal: 190,
                        max: 230
                    )
            } detail: {
                ConfigurationDetail(viewModel: viewModel)
            }

            Divider()
            ConfigurationFooter(viewModel: viewModel)
        }
        .frame(minWidth: 760, minHeight: 620)
    }
}

private struct ConfigurationAccessBanner: View {
    let viewModel: ConfigurationViewModel

    var body: some View {
        if let explanation = viewModel.sessionAccessExplanation {
            Label(explanation, systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.quaternary.opacity(0.5))
        } else if viewModel.presentationMode == .transcriptionRepair {
            Label(
                "Repair only the transcription provider or model. The retained recording is not uploaded until Retry.",
                systemImage: "wrench.and.screwdriver.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5))
        }
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
                Label(
                    issue.message,
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            } else if let success = viewModel.successMessage {
                Label(
                    success,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            } else {
                Label(
                    footerDetail,
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

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
                .disabled(!viewModel.canSave)
            }
        }
        .padding(18)
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
