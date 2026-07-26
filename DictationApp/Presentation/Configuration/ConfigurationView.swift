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
                    credentialSection
                    transcriptionSection
                    postProcessingSection
                    resultMessage
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(minWidth: 640, minHeight: 660)
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
                    viewModel.isFirstRun
                        ? "Set up DictationApp"
                        : "DictationApp Settings"
                )
                .font(.title2.weight(.semibold))

                Text(
                    "Configure cloud transcription and optional transcript cleanup."
                )
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
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
            }

            SecureField(
                viewModel.credentialExists
                    ? "Enter a new key to replace the saved key"
                    : "Enter your OpenAI API key",
                text: $viewModel.candidateAPIKey
            )
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.isValidating)

            HStack {
                Text(
                    "The key is stored in macOS Keychain and is never shown again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if viewModel.credentialExists {
                    Button("Delete", role: .destructive) {
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
            }

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
            }

            uploadNotice(
                "Saving a new key or custom transcription model uploads a " +
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

            if viewModel.postProcessingEnabled {
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
        } else if let successMessage = viewModel.successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
    }

    private var footer: some View {
        HStack {
            Label(
                "No microphone or Accessibility permission is requested here.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button(viewModel.saveButtonTitle) {
                Task {
                    await viewModel.save()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave)
            .overlay(alignment: .leading) {
                if viewModel.isValidating {
                    ProgressView()
                        .controlSize(.small)
                        .offset(x: -24)
                }
            }
        }
        .padding(20)
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
}
