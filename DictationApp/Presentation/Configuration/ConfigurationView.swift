import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @FocusState private var focusedField: ConfigurationField?

    var body: some View {
        VStack(spacing: 0) {
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

            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(
                        min: 170,
                        ideal: 190,
                        max: 230
                    )
            } detail: {
                detail
            }

            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 620)
        .onChange(of: viewModel.issues) {
            focusedField = viewModel.issues.first?.field
        }
        .onChange(of: viewModel.transcriptionProviderChoice) {
            viewModel.clearIssue(for: .transcriptionProvider)
        }
        .onChange(of: viewModel.transcriptionModelChoice) {
            viewModel.clearIssue(for: .transcriptionModel)
        }
        .onChange(of: viewModel.transcriptionCustomModel) {
            viewModel.clearIssue(for: .transcriptionModel)
        }
        .onChange(of: viewModel.languageCode) {
            viewModel.clearIssue(for: .language)
        }
        .onChange(of: viewModel.postProcessingProviderChoice) {
            viewModel.clearIssue(for: .postProcessingProvider)
        }
        .onChange(of: viewModel.postProcessingModelChoice) {
            viewModel.clearIssue(for: .postProcessingModel)
        }
        .onChange(of: viewModel.postProcessingCustomModel) {
            viewModel.clearIssue(for: .postProcessingModel)
        }
    }

    private var sidebar: some View {
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

    @ViewBuilder
    private var detail: some View {
        switch viewModel.selectedDestination {
        case .general:
            page(
                title: "General",
                detail:
                    "Permissions, shortcut, feedback, and privacy behavior."
            ) {
                permissionsSection
                shortcutSection
                feedbackSection
                privacySection
            }
            .disabled(!canEdit(.general) || viewModel.isValidating)
        case .transcription:
            page(
                title: "Transcription",
                detail:
                    "Choose how completed recordings become text."
            ) {
                transcriptionSection
            }
            .disabled(!canEdit(.transcription) || viewModel.isValidating)
        case .postProcessing:
            page(
                title: "Post-processing",
                detail:
                    "Optionally clean punctuation and formatting."
            ) {
                postProcessingSection
            }
            .disabled(!canEdit(.postProcessing) || viewModel.isValidating)
        case .providers:
            providersPage
                .disabled(!canEdit(.providers) || viewModel.isValidating)
        }
    }

    private func page<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader(title: title, detail: detail)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
    }

    private func pageHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var permissionsSection: some View {
        settingsGroup("Permissions", systemImage: "hand.raised") {
            LabeledContent("Microphone") {
                HStack(spacing: 10) {
                    permissionStatusLabel(
                        microphoneStatusTitle,
                        granted:
                            viewModel.microphoneStatus == .granted
                    )
                    microphoneAction
                }
            }

            Text(microphonePermissionExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("Accessibility") {
                HStack(spacing: 10) {
                    permissionStatusLabel(
                        accessibilityStatusTitle,
                        granted:
                            viewModel.accessibilityStatus == .granted
                    )
                    accessibilityAction
                }
            }

            Text(
                "Accessibility enables automatic insertion. Dictation remains available through the clipboard without it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var microphoneAction: some View {
        switch viewModel.microphoneStatus {
        case .notDetermined:
            AccessibleActionButton(
                title: "Enable",
                accessibilityLabel: "Enable microphone access",
                accessibilityHelp: "Requests permission from macOS."
            ) {
                Task {
                    await viewModel.enableMicrophone()
                }
            }
        case .denied, .restricted:
            AccessibleActionButton(
                title: "Open System Settings",
                accessibilityLabel: "Open Microphone settings",
                accessibilityHelp:
                    "Opens the macOS Microphone privacy settings."
            ) {
                viewModel.openMicrophoneSettings()
            }
        case .granted:
            EmptyView()
        }
    }

    @ViewBuilder
    private var accessibilityAction: some View {
        if viewModel.accessibilityStatus == .notGranted {
            AccessibleActionButton(
                title: "Enable",
                accessibilityLabel: "Enable Accessibility access",
                accessibilityHelp:
                    "Starts the macOS Accessibility trust flow."
            ) {
                viewModel.enableAccessibility()
            }

            AccessibleActionButton(
                title: "Open System Settings",
                accessibilityLabel: "Open Accessibility settings",
                accessibilityHelp:
                    "Opens the macOS Accessibility privacy settings."
            ) {
                viewModel.openAccessibilitySettings()
            }
        }
    }

    private var shortcutSection: some View {
        settingsGroup("Global Shortcut", systemImage: "keyboard") {
            ShortcutRecorder(
                shortcut: viewModel.globalShortcut,
                isEnabled: true,
                onCandidate: viewModel.updateGlobalShortcut
            )

            HStack {
                Text(
                    "The saved shortcut stays active until Save Changes succeeds."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Reset to Option–Space") {
                    viewModel.resetGlobalShortcut()
                }
                .disabled(
                    viewModel.globalShortcut
                        == GlobalShortcut.defaultShortcut
                )
            }

            if let message = viewModel.shortcutErrorMessage {
                issueLabel(message)
            }
        }
    }

    private var feedbackSection: some View {
        settingsGroup("Feedback", systemImage: "speaker.wave.2") {
            Toggle(
                "Play start, stop, cancel, and failure sounds",
                isOn: $viewModel.soundCuesEnabled
            )
        }
    }

    private var privacySection: some View {
        settingsGroup("Data & Privacy", systemImage: "lock.shield") {
            Label(
                "Provider credentials are stored in macOS Keychain.",
                systemImage: "key.fill"
            )
            privacyFlow(
                capability: .transcription,
                provider: viewModel.transcriptionProviderChoice
            )
            if viewModel.postProcessingEnabled {
                privacyFlow(
                    capability: .postProcessing,
                    provider: viewModel.postProcessingProviderChoice
                )
            } else {
                Label(
                    "Post-processing is disabled; raw transcripts are not sent for cleanup.",
                    systemImage: "text.badge.xmark"
                )
            }
            Label(
                "DictationApp has no account or proprietary backend and does not retain completed session data.",
                systemImage: "externaldrive.badge.checkmark"
            )
        }
        .font(.callout)
    }

    @ViewBuilder
    private func privacyFlow(
        capability: ProviderCapability,
        provider: ProviderID
    ) -> some View {
        if
            let descriptor = viewModel.descriptor(for: provider),
            let metadata = descriptor.capabilities[capability]
        {
            Label(
                metadata.dataFlowDescription,
                systemImage:
                    metadata.processingLocation == .cloud
                    ? "icloud.and.arrow.up"
                    : "desktopcomputer"
            )
        }
    }

    private var transcriptionSection: some View {
        settingsGroup("Transcription", systemImage: "waveform") {
            if viewModel.availableTranscriptionProviders.isEmpty {
                noProviderConfigured(capability: .transcription)
            } else {
                LabeledContent("Provider") {
                    Picker(
                        "Transcription provider",
                        selection: Binding(
                            get: {
                                viewModel.transcriptionProviderChoice
                            },
                            set: {
                                viewModel.selectTranscriptionProvider($0)
                            }
                        )
                    ) {
                        ForEach(
                            viewModel.availableTranscriptionProviders
                        ) { provider in
                            providerPickerLabel(
                                provider,
                                capability: .transcription
                            )
                            .tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }
            }

            LabeledContent("Model") {
                Picker(
                    "Transcription model",
                    selection: $viewModel.transcriptionModelChoice
                ) {
                    ForEach(
                        viewModel.modelCatalog(
                            for: viewModel.transcriptionProviderChoice,
                            capability: .transcription
                        )
                    ) {
                        model in
                        modelLabel(model).tag(model.id)
                    }
                    if
                        viewModel.supportsCustomModels(
                            provider:
                                viewModel.transcriptionProviderChoice,
                            capability: .transcription
                        )
                    {
                        Divider()
                        Text("Advanced: Custom model")
                            .tag(
                                ConfigurationViewModel.customModelChoice
                            )
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
            }

            if
                viewModel.transcriptionModelChoice
                    == ConfigurationViewModel.customModelChoice
            {
                TextField(
                    "Custom model identifier",
                    text: $viewModel.transcriptionCustomModel
                )
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .transcriptionModel)
                .accessibilityLabel(
                    "Custom transcription model identifier"
                )
            }

            if
                let issue = viewModel.issue(
                    for: .transcriptionModel
                )
            {
                issueLabel(issue.message)
            }

            if viewModel.presentationMode == .full {
                LabeledContent("Language") {
                    Picker(
                        "Language",
                        selection: $viewModel.languageCode
                    ) {
                        Text("Automatic").tag("")
                        Divider()
                        ForEach(viewModel.availableLanguages) { language in
                            Text(language.displayName).tag(language.id)
                        }
                        if viewModel.hasUnsupportedLanguageSelection {
                            Divider()
                            Text(
                                "\(viewModel.languageCode) — Unsupported"
                            )
                            .tag(viewModel.languageCode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .focused($focusedField, equals: .language)
                }
                if viewModel.hasUnsupportedLanguageSelection {
                    issueLabel(
                        "The selected provider does not support this language.",
                        warning: true
                    )
                }
            } else {
                LabeledContent("Language") {
                    Text(viewModel.repairLanguageTitle)
                        .foregroundStyle(.secondary)
                }
            }

            stageDisclosure(
                provider: viewModel.transcriptionProviderChoice,
                capability: .transcription
            )
        }
    }

    private var postProcessingSection: some View {
        settingsGroup(
            "Transcript cleanup",
            systemImage: "wand.and.stars"
        ) {
            Toggle(
                "Enable transcript cleanup",
                isOn: $viewModel.postProcessingEnabled
            )

            if viewModel.postProcessingEnabled {
                if
                    let attention =
                        viewModel.postProcessingAttentionMessage
                {
                    issueLabel(attention, warning: true)
                }

                if viewModel.availablePostProcessingProviders.isEmpty {
                    noProviderConfigured(
                        capability: .postProcessing
                    )
                } else {
                    LabeledContent("Provider") {
                        Picker(
                            "Post-processing provider",
                            selection: Binding(
                                get: {
                                    viewModel
                                        .postProcessingProviderChoice
                                },
                                set: {
                                    viewModel
                                        .selectPostProcessingProvider($0)
                                }
                            )
                        ) {
                            ForEach(
                                viewModel
                                    .availablePostProcessingProviders
                            ) { provider in
                                providerPickerLabel(
                                    provider,
                                    capability: .postProcessing
                                )
                                .tag(provider.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }
                }

                LabeledContent("Model") {
                    Picker(
                        "Post-processing model",
                        selection:
                            $viewModel.postProcessingModelChoice
                    ) {
                        ForEach(
                            viewModel.modelCatalog(
                                for:
                                    viewModel
                                        .postProcessingProviderChoice,
                                capability: .postProcessing
                            )
                        ) { model in
                            modelLabel(model).tag(model.id)
                        }
                        if
                            viewModel.supportsCustomModels(
                                provider:
                                    viewModel
                                        .postProcessingProviderChoice,
                                capability: .postProcessing
                            )
                        {
                            Divider()
                            Text("Advanced: Custom model")
                                .tag(
                                    ConfigurationViewModel
                                        .customModelChoice
                                )
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                if
                    viewModel.postProcessingModelChoice
                        == ConfigurationViewModel.customModelChoice
                {
                    TextField(
                        "Custom model identifier",
                        text: $viewModel.postProcessingCustomModel
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused(
                        $focusedField,
                        equals: .postProcessingModel
                    )
                    .accessibilityLabel(
                        "Custom post-processing model identifier"
                    )
                }

                if
                    let issue = viewModel.issue(
                        for: .postProcessingModel
                    )
                {
                    issueLabel(issue.message)
                }

                stageDisclosure(
                    provider:
                        viewModel.postProcessingProviderChoice,
                    capability: .postProcessing
                )
            } else {
                Text(
                    "The raw transcript is inserted without an additional provider request."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var providersPage: some View {
        NavigationStack {
            page(
                title: "Providers",
                detail:
                    "Configure implemented providers and review their capabilities."
            ) {
                ForEach(viewModel.providerRegistry.settingsModules) {
                    module in
                    Button {
                        viewModel.showProvider(module.id)
                    } label: {
                        providerRow(module)
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
                providerDetail(providerID)
            }
        }
    }

    private func providerDetail(_ providerID: ProviderID) -> some View {
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
                                "Provider-specific connection and authentication settings."
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
                        settingsGroup(
                            "Configuration",
                            systemImage: "key"
                        ) {
                            module.makeDetailView()
                        }

                        settingsGroup(
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
                            issueLabel(issue.message)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
    }

    private func providerRow(
        _ module: AnyProviderSettingsModule
    ) -> some View {
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

            providerStatus(module.readiness)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func providerStatus(
        _ readiness: ProviderReadiness
    ) -> some View {
        Label(
            readinessTitle(readiness),
            systemImage: readinessSystemImage(readiness)
        )
        .font(.caption)
        .foregroundStyle(
            readiness.state == .configured ? Color.green : Color.orange
        )
    }

    private func noProviderConfigured(
        capability: ProviderCapability
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "No provider configured",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
            Text(
                "Configure a provider that supports \(capability.displayName.lowercased())."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Configure Providers") {
                viewModel.selectedDestination = .providers
            }
        }
    }

    private func providerPickerLabel(
        _ descriptor: ProviderDescriptor,
        capability: ProviderCapability
    ) -> some View {
        HStack {
            Text(descriptor.displayName)
            if let metadata = descriptor.capabilities[capability] {
                Text("— \(metadata.processingLocation.displayName)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stageDisclosure(
        provider: ProviderID,
        capability: ProviderCapability
    ) -> some View {
        if
            let descriptor = viewModel.descriptor(for: provider),
            let metadata = descriptor.capabilities[capability]
        {
            Label(
                metadata.dataFlowDescription,
                systemImage:
                    metadata.processingLocation == .cloud
                    ? "icloud.and.arrow.up"
                    : "desktopcomputer"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
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

    private func hasAttention(
        _ destination: SettingsDestination
    ) -> Bool {
        switch destination {
        case .providers:
            return viewModel.providerRegistry.settingsModules.contains {
                $0.readiness.state == .attentionRequired
                    || $0.readiness.state == .setupRequired
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

    private func settingsGroup<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func modelLabel(
        _ model: ProviderModelDescriptor
    ) -> some View {
        HStack {
            Text(model.displayName)
            if let detail = model.detail {
                Text("— \(detail)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionStatusLabel(
        _ title: String,
        granted: Bool
    ) -> some View {
        Label(
            title,
            systemImage:
                granted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle"
        )
        .foregroundStyle(granted ? Color.green : Color.secondary)
    }

    private func issueLabel(
        _ message: String,
        warning: Bool = false
    ) -> some View {
        Label(
            message,
            systemImage:
                warning
                ? "exclamationmark.triangle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(warning ? Color.orange : Color.red)
    }

    private var microphoneStatusTitle: String {
        switch viewModel.microphoneStatus {
        case .notDetermined:
            "Not requested"
        case .granted:
            "Enabled"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }

    private var microphonePermissionExplanation: String {
        switch viewModel.microphoneStatus {
        case .notDetermined:
            "Enable microphone access now or allow it when starting the first recording."
        case .granted:
            "DictationApp can record from the current macOS default input device."
        case .denied:
            "Recording remains unavailable until access is enabled in System Settings."
        case .restricted:
            "Microphone access is restricted by macOS or device policy."
        }
    }

    private var accessibilityStatusTitle: String {
        viewModel.accessibilityStatus == .granted
            ? "Enabled"
            : "Not enabled"
    }

    private func readinessTitle(
        _ readiness: ProviderReadiness
    ) -> String {
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

    private func readinessSystemImage(
        _ readiness: ProviderReadiness
    ) -> String {
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
