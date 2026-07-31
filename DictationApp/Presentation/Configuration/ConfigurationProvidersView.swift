import SwiftUI

struct ConfigurationProvidersView: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        NavigationStack {
            ConfigurationPage(
                title: "Providers",
                detail:
                    "Configure implemented providers and review their capabilities."
            ) {
                ForEach(viewModel.providerRegistry.settingsModules) {
                    module in
                    Button {
                        viewModel.showProvider(module.id)
                    } label: {
                        ConfigurationProviderRow(module: module)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        "Opens \(module.descriptor.displayName) settings."
                    )
                }
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
}

private struct ConfigurationProviderDetailView: View {
    let viewModel: ConfigurationViewModel
    let providerID: ProviderID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if let descriptor = viewModel.descriptor(for: providerID) {
                    HStack(spacing: 12) {
                        Image(systemName: descriptor.systemImage)
                            .font(.title)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(descriptor.displayName)
                                .font(.title2.weight(.semibold))
                            Text(
                                providerID == .appleOnDevice
                                    ? "On-device availability, permission, and language assets."
                                    : "Provider-specific connection and authentication settings."
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if
                        let module =
                            viewModel.providerRegistry.settingsModule(
                                for: providerID
                            )
                    {
                        ConfigurationSettingsGroup(
                            "Configuration",
                            systemImage:
                                providerID == .appleOnDevice
                                ? "internaldrive"
                                : "key"
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

                        ConfigurationSettingsGroup(
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
                                    LabeledContent(
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
    }
}

private struct ConfigurationProviderRow: View {
    @ObservedObject var module: AnyProviderSettingsModule

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: module.descriptor.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 7) {
                Text(module.descriptor.displayName)
                    .font(.headline)

                HStack(spacing: 6) {
                    ForEach(
                        module.descriptor.capabilities.keys.sorted {
                            $0.rawValue < $1.rawValue
                        },
                        id: \.self
                    ) { capability in
                        Text(capability.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            ConfigurationProviderStatus(readiness: module.readiness)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

private struct ConfigurationProviderStatus: View {
    let readiness: ProviderReadiness

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(
                readiness.state == .configured
                    ? Color.green
                    : Color.orange
            )
    }

    private var title: String {
        switch readiness.state {
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
}
