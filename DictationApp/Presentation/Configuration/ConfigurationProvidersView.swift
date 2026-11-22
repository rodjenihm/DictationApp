import SwiftUI

struct ConfigurationProvidersView: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        NavigationStack {
            ConfigurationPage(
                title: "Providers",
                detail: "Manage provider setup and see where your data is processed.",
                systemImage: SettingsDestination.providers.systemImage
            ) {
                VStack(spacing: 10) {
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
            Button("Providers", systemImage: "chevron.left") {
                viewModel.showProvidersList()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to Providers")
            .accessibilityLabel("Back to Providers")
            .padding(.horizontal, 28)
            .padding(.top, 14)

            if let module = viewModel.providerRegistry.settingsModule(for: providerID) {
                ConfigurationPage(
                    title: module.descriptor.displayName,
                    detail: providerDetail,
                    systemImage: module.descriptor.systemImage
                ) {
                    ConfigurationSection(
                        "Configuration",
                        systemImage: providerID == .openAI ? "key" : "internaldrive"
                    ) {
                        module.makeDetailView()
                    }
                    .configurationPanel()

                    if providerID == .appleOnDevice, viewModel.isFirstRun {
                        Button("Use OpenAI instead") {
                            viewModel.useOpenAIForTranscription()
                        }
                    }

                    ConfigurationSection("Capabilities", systemImage: "checklist") {
                        ForEach(
                            module.descriptor.capabilities.keys.sorted {
                                $0.rawValue < $1.rawValue
                            },
                            id: \.self
                        ) { capability in
                            if let metadata = module.descriptor.capabilities[capability] {
                                ConfigurationSettingRow(capability.displayName) {
                                    Text(metadata.processingLocation.displayName)
                                }
                            }
                        }
                    }

                    if let issue = viewModel.issue(for: .credential(providerID)) {
                        ConfigurationIssueLabel(message: issue.message)
                    }
                }
            }
        }
        .background(ConfigurationAppearance.canvas)
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
    @State private var isHovered = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ConfigurationEmblem(systemImage: module.descriptor.systemImage, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(module.descriptor.displayName)
                    .font(.headline)

                Text(capabilities)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dynamicTypeSize.isAccessibilitySize {
                    ConfigurationProviderStatus(readiness: module.readiness)
                }
            }

            Spacer(minLength: 8)

            if !dynamicTypeSize.isAccessibilitySize {
                ConfigurationProviderStatus(readiness: module.readiness)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isHovered ? ConfigurationAppearance.highlight : ConfigurationAppearance.surface,
            in: .rect(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ConfigurationAppearance.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
    }

    private var capabilities: String {
        module.descriptor.capabilities.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: " · ")
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
