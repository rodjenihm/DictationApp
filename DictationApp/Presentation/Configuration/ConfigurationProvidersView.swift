import SwiftUI

struct ConfigurationProvidersView: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        NavigationStack {
            ConfigurationPage(
                title: "Providers",
                detail: "Configure providers and review where they process data."
            ) {
                VStack(spacing: 8) {
                    ForEach(viewModel.providerRegistry.settingsModules) {
                        module in
                        Button {
                            viewModel.showProvider(module.id)
                        } label: {
                            ConfigurationProviderRow(module: module)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            module.descriptor.displayName
                        )
                        .accessibilityValue(
                            providerAccessibilityValue(module)
                        )
                        .accessibilityHint(
                            "Opens \(module.descriptor.displayName) settings."
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationDestination(
                item: $viewModel.selectedProviderDetail
            ) { providerID in
                ConfigurationProviderDetailView(
                    viewModel: viewModel,
                    providerID: providerID
                )
            }
        }
    }

    private func providerAccessibilityValue(
        _ module: AnyProviderSettingsModule
    ) -> String {
        let capabilities = module.descriptor.capabilities.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: ", ")
        return "\(module.descriptor.displayName). "
            + "\(module.readiness.state.settingsTitle). "
            + "Capabilities: \(capabilities)."
    }
}

private struct ConfigurationProviderDetailView: View {
    let viewModel: ConfigurationViewModel
    let providerID: ProviderID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Providers", systemImage: "chevron.left") {
                    viewModel.showProvidersList()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to Providers")
                .accessibilityLabel("Back to Providers")

                if let descriptor = viewModel.descriptor(for: providerID) {
                    HStack(spacing: 10) {
                        Image(systemName: descriptor.systemImage)
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(descriptor.displayName)
                                .font(.title3.weight(.semibold))
                            Text(providerDetail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if
                        let module =
                            viewModel.providerRegistry.settingsModule(
                                for: providerID
                            )
                    {
                        ConfigurationSection(
                            "Configuration",
                            systemImage:
                                providerID == .openAI
                                ? "key"
                                : "internaldrive"
                        ) {
                            module.makeDetailView()
                        }

                        if
                            providerID == .appleOnDevice,
                            viewModel.isFirstRun
                        {
                            Button("Use OpenAI instead") {
                                viewModel.useOpenAIForTranscription()
                            }
                        }

                        ConfigurationSection(
                            "Capabilities",
                            systemImage: "checklist"
                        ) {
                            ForEach(
                                module.descriptor.capabilities.keys.sorted {
                                    $0.rawValue < $1.rawValue
                                },
                                id: \.self
                            ) { capability in
                                if
                                    let metadata =
                                        module.descriptor.capabilities[
                                            capability
                                        ]
                                {
                                    ConfigurationSettingRow(
                                        capability.displayName
                                    ) {
                                        Text(
                                            metadata.processingLocation
                                                .displayName
                                        )
                                    }
                                }
                            }
                        }

                        if
                            let issue = viewModel.issue(
                                for: .credential(providerID)
                            )
                        {
                            ConfigurationIssueLabel(
                                message: issue.message
                            )
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
    }

    private var providerDetail: String {
        switch providerID {
        case .appleOnDevice:
            "On-device availability, permission, and language assets."
        case .appleIntelligence:
            "Availability of the on-device transcript cleanup model."
        case .openAI:
            "Provider-specific connection and authentication settings."
        }
    }
}

private struct ConfigurationProviderRow: View {
    @ObservedObject var module: AnyProviderSettingsModule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.descriptor.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(module.descriptor.displayName)
                    .font(.headline)

                HStack(spacing: 5) {
                    ForEach(
                        module.descriptor.capabilities.keys.sorted {
                            $0.rawValue < $1.rawValue
                        },
                        id: \.self
                    ) { capability in
                        Text(capability.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 12)

            ConfigurationProviderStatus(readiness: module.readiness)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: 8))
    }
}

private struct ConfigurationProviderStatus: View {
    let readiness: ProviderReadiness

    var body: some View {
        ConfigurationStatusLabel(
            title: readiness.state.settingsTitle,
            systemImage: systemImage,
            style: style
        )
    }

    private var systemImage: String {
        switch readiness.state {
        case .configured:
            "checkmark.circle.fill"
        case .pendingValidation:
            "clock.fill"
        case .willDisconnect:
            "minus.circle.fill"
        case .setupRequired, .attentionRequired:
            "exclamationmark.triangle.fill"
        }
    }

    private var style: ConfigurationStatusStyle {
        switch readiness.state {
        case .configured:
            .success
        case .pendingValidation:
            .pending
        case
            .setupRequired,
            .attentionRequired,
            .willDisconnect:
            .attention
        }
    }
}

private extension ProviderReadinessState {
    var settingsTitle: String {
        switch self {
        case .configured:
            "Configured"
        case .setupRequired:
            "Setup required"
        case .attentionRequired:
            "Attention required"
        case .pendingValidation:
            "Pending validation"
        case .willDisconnect:
            "Will be disconnected"
        }
    }
}
