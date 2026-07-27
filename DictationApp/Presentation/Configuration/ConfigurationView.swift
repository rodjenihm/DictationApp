import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var isConfirmingCredentialDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let explanation =
                        viewModel.sessionAccessExplanation
                    {
                        Label(
                            explanation,
                            systemImage: "lock.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        .accessibilityLabel(
                            "Settings locked. \(explanation)"
                        )
                    }

                    if viewModel.presentationMode == .full {
                        permissionsSection
                        shortcutSection
                        feedbackSection
                    }
                    credentialSection
                    transcriptionSection
                    if viewModel.presentationMode == .full {
                        postProcessingSection
                    }
                    resultMessage
                }
                .disabled(!viewModel.canEditPresentedSettings)
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(minWidth: 660, minHeight: 700)
        .confirmationDialog(
            "Delete the saved OpenAI API key?",
            isPresented: $isConfirmingCredentialDeletion
        ) {
            Button("Delete API Key", role: .destructive) {
                viewModel.deleteCredential()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Transcription will remain unavailable until another key is " +
                    "validated and saved."
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    headerTitle
                )
                .font(.title2.weight(.semibold))

                Text(
                    headerDetail
                )
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }

    private var permissionsSection: some View {
        settingsGroup("Permissions", systemImage: "hand.raised") {
            LabeledContent("Microphone") {
                HStack(spacing: 10) {
                    permissionStatusLabel(
                        microphoneStatusTitle,
                        systemImage: microphoneStatusSystemImage,
                        color: microphoneStatusColor
                    )

                    switch viewModel.microphoneStatus {
                    case .notDetermined:
                        AccessibleActionButton(
                            title: "Enable",
                            accessibilityLabel:
                                "Enable microphone access",
                            accessibilityHelp:
                                "Requests permission from macOS."
                        ) {
                            Task {
                                await viewModel.enableMicrophone()
                            }
                        }
                    case .denied, .restricted:
                        AccessibleActionButton(
                            title: "Open System Settings",
                            accessibilityLabel:
                                "Open Microphone settings",
                            accessibilityHelp:
                                "Opens the macOS Microphone privacy settings."
                        ) {
                            viewModel.openMicrophoneSettings()
                        }
                    case .granted:
                        EmptyView()
                    }
                }
            }

            Text(
                microphonePermissionExplanation
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(
                "Microphone status: \(microphoneStatusTitle). " +
                    microphonePermissionExplanation
            )

            Divider()

            LabeledContent("Accessibility") {
                HStack(spacing: 10) {
                    permissionStatusLabel(
                        accessibilityStatusTitle,
                        systemImage: accessibilityStatusSystemImage,
                        color: accessibilityStatusColor
                    )

                    if viewModel.accessibilityStatus == .notGranted {
                        AccessibleActionButton(
                            title: "Enable",
                            accessibilityLabel:
                                "Enable Accessibility access",
                            accessibilityHelp:
                                "Starts the macOS trust flow for automatic insertion."
                        ) {
                            viewModel.enableAccessibility()
                        }

                        AccessibleActionButton(
                            title: "Open System Settings",
                            accessibilityLabel:
                                "Open Accessibility settings",
                            accessibilityHelp:
                                "Opens the macOS Accessibility privacy settings."
                        ) {
                            viewModel.openAccessibilitySettings()
                        }
                    }
                }
            }

            Text(
                "Accessibility enables automatic insertion. It is optional; " +
                    "without it, completed transcripts remain on the clipboard. " +
                    "In System Settings, use Privacy & Security → Accessibility."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(
                "Accessibility status: \(accessibilityStatusTitle). " +
                    "Accessibility is optional and enables automatic insertion."
            )
        }
    }

    private var shortcutSection: some View {
        settingsGroup("Global Shortcut", systemImage: "keyboard") {
            LabeledContent("Start or stop dictation") {
                ShortcutRecorder(
                    shortcut: viewModel.globalShortcut,
                    isEnabled:
                        viewModel.canEditPresentedSettings
                        && !viewModel.isValidating,
                    onCandidate: viewModel.updateGlobalShortcut
                )
                .frame(width: 180, height: 28)
                .accessibilityLabel("Global dictation shortcut")
                .accessibilityValue(
                    viewModel.globalShortcut.displayName
                )
                .accessibilityHint(
                    "Press Space or Return to record a replacement shortcut. " +
                        "Press Escape while recording a shortcut to cancel."
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(
                    "Click the shortcut, then press a key with Command, " +
                        "Option, Control, or Shift. During an active dictation " +
                        "session, Escape cancels the session."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer()

                AccessibleActionButton(
                    title: "Reset to Option–Space",
                    accessibilityLabel:
                        "Reset global shortcut to Option–Space",
                    accessibilityHelp:
                        "Restores the default global dictation shortcut."
                ) {
                    viewModel.resetGlobalShortcut()
                }
                .disabled(
                    viewModel.globalShortcut == .defaultShortcut
                        || viewModel.isValidating
                )
            }

            if let error = viewModel.shortcutErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let success = viewModel.shortcutSuccessMessage {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }

    private var feedbackSection: some View {
        settingsGroup("Feedback", systemImage: "speaker.wave.2") {
            Toggle(
                "Play sound cues",
                isOn: $viewModel.soundCuesEnabled
            )
            .disabled(viewModel.isValidating)
            .accessibilityHint(
                "Controls all recording and attention sound cues."
            )

            Text(
                "Plays distinct cues when recording starts, stops, is " +
                    "cancelled, or requires attention. Sounds use the current " +
                    "macOS output device and volume."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialSection: some View {
        settingsGroup("OpenAI Credential", systemImage: "key") {
            LabeledContent("Status") {
                Label(
                    viewModel.credentialExists
                        ? "API key saved"
                        : "No API key saved",
                    systemImage: viewModel.credentialExists
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
                )
                .foregroundStyle(
                    viewModel.credentialExists ? Color.green : Color.secondary
                )
                .accessibilityLabel("OpenAI API key status")
                .accessibilityValue(
                    viewModel.credentialExists
                        ? "Saved"
                        : "Not saved"
                )
            }

            SecureField(
                viewModel.credentialExists
                    ? "Enter a new key to replace the saved key"
                    : "Enter your OpenAI API key",
                text: $viewModel.candidateAPIKey
            )
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.isValidating)
            .accessibilityLabel("OpenAI API key")
            .accessibilityHint(
                viewModel.credentialExists
                    ? "Enter a replacement key. The saved key is never displayed."
                    : "Enter the key that will be stored in macOS Keychain."
            )

            HStack {
                Text(
                    "The key is stored in macOS Keychain and is never shown again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if
                    viewModel.credentialExists
                        && viewModel.presentationMode == .full
                {
                    AccessibleActionButton(
                        title: "Delete",
                        accessibilityLabel:
                            "Delete saved OpenAI API key",
                        accessibilityHelp:
                            "Opens a confirmation before removing the saved key."
                    ) {
                        isConfirmingCredentialDeletion = true
                    }
                    .disabled(viewModel.isValidating)
                }
            }
        }
    }

    private var transcriptionSection: some View {
        settingsGroup("Transcription", systemImage: "waveform") {
            LabeledContent("Provider") {
                Text(ProviderID.openAI.displayName)
            }

            LabeledContent("Model") {
                Picker(
                    "Transcription model",
                    selection: $viewModel.transcriptionModelChoice
                ) {
                    ForEach(OpenAIModelCatalog.transcriptionModels) { model in
                        modelLabel(model).tag(model.id)
                    }
                    Divider()
                    Text("Advanced: Custom model")
                        .tag(ConfigurationViewModel.customModelChoice)
                }
                .labelsHidden()
                .frame(maxWidth: 300)
                .disabled(viewModel.isValidating)
                .accessibilityLabel("Transcription model")
                .accessibilityHint(
                    "Selects the OpenAI model used for completed audio."
                )
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
                .disabled(viewModel.isValidating)
                .accessibilityLabel(
                    "Custom transcription model identifier"
                )
            }

            if viewModel.presentationMode == .full {
                LabeledContent("Language") {
                    Picker("Language", selection: $viewModel.languageCode) {
                        Text("Automatic").tag("")
                        Divider()
                        ForEach(OpenAIModelCatalog.languages) { language in
                            Text(language.displayName).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    .disabled(viewModel.isValidating)
                    .accessibilityLabel(
                        "Transcription language hint"
                    )
                    .accessibilityHint(
                        "Automatic sends no language hint and does not translate."
                    )
                }
            }

            uploadNotice(
                viewModel.presentationMode == .transcriptionRepair
                    ? "Validation uploads only the bundled 0.75-second silent " +
                        "M4A file to OpenAI. The retained recording is not " +
                        "uploaded until you explicitly retry."
                    : "Saving a new key or custom transcription model uploads a " +
                        "bundled 0.75-second silent M4A file to OpenAI. Future " +
                        "dictation audio will be uploaded only after recording stops."
            )
        }
    }

    private var postProcessingSection: some View {
        settingsGroup("Post-processing", systemImage: "wand.and.stars") {
            Toggle(
                "Clean up punctuation and formatting",
                isOn: $viewModel.postProcessingEnabled
            )
            .disabled(viewModel.isValidating)
            .accessibilityHint(
                "When enabled, each raw transcript is sent to OpenAI for cleanup."
            )

            if viewModel.postProcessingEnabled {
                if
                    let attentionMessage =
                        viewModel.postProcessingAttentionMessage
                {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "Needs Attention",
                            systemImage:
                                "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .accessibilityLabel(
                            "Post-processing needs attention"
                        )

                        Text(attentionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                }

                LabeledContent("Provider") {
                    Text(ProviderID.openAI.displayName)
                }

                LabeledContent("Model") {
                    Picker(
                        "Post-processing model",
                        selection: $viewModel.postProcessingModelChoice
                    ) {
                        ForEach(
                            OpenAIModelCatalog.postProcessingModels
                        ) { model in
                            modelLabel(model).tag(model.id)
                        }
                        Divider()
                        Text("Advanced: Custom model")
                            .tag(ConfigurationViewModel.customModelChoice)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    .disabled(viewModel.isValidating)
                    .accessibilityLabel("Post-processing model")
                    .accessibilityHint(
                        "Selects the OpenAI model used to clean raw transcripts."
                    )
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
                    .disabled(viewModel.isValidating)
                    .accessibilityLabel(
                        "Custom post-processing model identifier"
                    )
                }

                uploadNotice(
                    "Enabling or changing cleanup sends a fixed minimal " +
                        "validation text to OpenAI. When enabled, each raw " +
                        "transcript will also be sent to OpenAI."
                )
            } else {
                Text(
                    "Disabled returns the raw transcript and makes no cleanup request."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultMessage: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .accessibilityLabel(
                    "Configuration error. \(errorMessage)"
                )
        } else if let successMessage = viewModel.successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .accessibilityLabel(
                    "Configuration status. \(successMessage)"
                )
        }
    }

    private var footer: some View {
        HStack {
            Label(
                footerDetail,
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            AccessibleActionButton(
                title: viewModel.saveButtonTitle,
                accessibilityLabel: viewModel.saveButtonTitle,
                accessibilityHelp:
                    "Validates required cloud configuration before saving.",
                isDefault: true
            ) {
                Task {
                    await viewModel.save()
                }
            }
            .disabled(!viewModel.canSave)
            .overlay(alignment: .leading) {
                if viewModel.isValidating {
                    ProgressView()
                        .controlSize(.small)
                        .offset(x: -24)
                        .accessibilityLabel(
                            "Validating configuration"
                        )
                }
            }
        }
        .padding(20)
    }

    private var headerTitle: String {
        switch viewModel.presentationMode {
        case .full:
            viewModel.isFirstRun
                ? "Set up DictationApp"
                : "DictationApp Settings"
        case .transcriptionRepair:
            "Repair Transcription"
        }
    }

    private var headerDetail: String {
        switch viewModel.presentationMode {
        case .full:
            "Configure cloud transcription and optional transcript cleanup."
        case .transcriptionRepair:
            "Validate an API key and transcription model for the retained recording."
        }
    }

    private var footerDetail: String {
        switch viewModel.presentationMode {
        case .full:
            "Opening Settings never requests permissions; Enable actions are explicit."
        case .transcriptionRepair:
            "Language, recording, and post-processing settings remain fixed for this session."
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

    private func uploadNotice(_ text: String) -> some View {
        Label(text, systemImage: "icloud.and.arrow.up")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func modelLabel(_ model: ProviderModel) -> some View {
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
        systemImage: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(color)
    }

    private var microphoneStatusTitle: String {
        switch viewModel.microphoneStatus {
        case .notDetermined:
            "Not requested"
        case .granted:
            "Allowed"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }

    private var microphoneStatusSystemImage: String {
        switch viewModel.microphoneStatus {
        case .granted:
            "checkmark.circle.fill"
        case .notDetermined:
            "circle.dashed"
        case .denied, .restricted:
            "exclamationmark.circle"
        }
    }

    private var microphoneStatusColor: Color {
        switch viewModel.microphoneStatus {
        case .granted:
            .green
        case .notDetermined:
            .secondary
        case .denied, .restricted:
            .orange
        }
    }

    private var microphonePermissionExplanation: String {
        switch viewModel.microphoneStatus {
        case .notDetermined:
            "Microphone access is required to record dictation. It will also " +
                "be requested just in time on the first recording attempt."
        case .granted:
            "Microphone access is available for local recording."
        case .denied:
            "Recording is unavailable until DictationApp is enabled in " +
                "System Settings → Privacy & Security → Microphone."
        case .restricted:
            "Microphone access is restricted by this Mac's policy. Recording " +
                "is unavailable while the restriction remains."
        }
    }

    private var accessibilityStatusTitle: String {
        switch viewModel.accessibilityStatus {
        case .granted:
            "Allowed"
        case .notGranted:
            "Not allowed"
        }
    }

    private var accessibilityStatusSystemImage: String {
        switch viewModel.accessibilityStatus {
        case .granted:
            "checkmark.circle.fill"
        case .notGranted:
            "circle.dashed"
        }
    }

    private var accessibilityStatusColor: Color {
        switch viewModel.accessibilityStatus {
        case .granted:
            .green
        case .notGranted:
            .secondary
        }
    }
}
