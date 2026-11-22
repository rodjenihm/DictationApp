import SwiftUI

struct ConfigurationTranscriptionView: View {
    @Bindable var viewModel: ConfigurationViewModel
    @FocusState private var focusedField: ConfigurationField?

    var body: some View {
        ConfigurationPage(
            title: "Transcription",
            detail: "Choose how dictation audio becomes text."
        ) {
            ConfigurationForm {
                providerSelection
                if
                    viewModel.hasModelSelection(
                        provider:
                            viewModel.transcriptionProviderChoice,
                        capability: .transcription
                    )
                {
                    modelSelection
                }
                languageSelection
                ConfigurationFormSupplementary {
                    ConfigurationStageDisclosure(
                        viewModel: viewModel,
                        provider: viewModel.transcriptionProviderChoice,
                        capability: .transcription
                    )
                }
            }
        }
        .onChange(of: viewModel.issues, initial: true) {
            routeIssueFocus()
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
    }

    @ViewBuilder
    private var providerSelection: some View {
        if viewModel.availableTranscriptionProviders.isEmpty {
            ConfigurationNoProviderView(
                viewModel: viewModel,
                capability: .transcription
            )
        } else {
            ConfigurationSettingRow("Provider") {
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
                        ConfigurationProviderPickerLabel(
                            descriptor: provider,
                            capability: .transcription
                        )
                        .tag(provider.id)
                    }
                }
                .labelsHidden()
                .configurationPickerControl()
            }
        }
    }

    @ViewBuilder
    private var modelSelection: some View {
        ConfigurationSettingRow("Model") {
            Picker(
                "Transcription model",
                selection: $viewModel.transcriptionModelChoice
            ) {
                ForEach(
                    transcriptionModelCatalog
                ) { model in
                    ConfigurationModelLabel(model: model)
                        .tag(model.id)
                }
                if
                    viewModel.supportsCustomModels(
                        provider: viewModel.transcriptionProviderChoice,
                        capability: .transcription
                    )
                {
                    Divider()
                    Text("Advanced: Custom model")
                        .tag(ConfigurationViewModel.customModelChoice)
                }
                if !hasTranscriptionModelPickerTag {
                    Divider()
                    Text(
                        viewModel.transcriptionModelChoice.isEmpty
                            ? "Choose a model"
                            : "Provider-managed model"
                    )
                    .tag(viewModel.transcriptionModelChoice)
                }
            }
            .labelsHidden()
            .configurationPickerControl()
        }

        if
            viewModel.transcriptionModelChoice
                == ConfigurationViewModel.customModelChoice
        {
            ConfigurationSettingRow("Custom model") {
                TextField(
                    "Custom model identifier",
                    text: $viewModel.transcriptionCustomModel
                )
                .textFieldStyle(.roundedBorder)
                .configurationFieldControl()
                .focused($focusedField, equals: .transcriptionModel)
                .accessibilityLabel(
                    "Custom transcription model identifier"
                )
            }
        }

        if let issue = viewModel.issue(for: .transcriptionModel) {
            ConfigurationFormSupplementary {
                ConfigurationIssueLabel(message: issue.message)
            }
        }
    }

    @ViewBuilder
    private var languageSelection: some View {
        if viewModel.presentationMode == .full {
            ConfigurationSettingRow("Language") {
                Picker(
                    "Language",
                    selection: $viewModel.languageCode
                ) {
                    if
                        viewModel
                            .allowsAutomaticTranscriptionLanguage
                    {
                        Text("Automatic").tag("")
                        Divider()
                    } else if viewModel.languageCode.isEmpty {
                        Text("Choose a language").tag("")
                        Divider()
                    }
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
                .configurationPickerControl()
                .focused($focusedField, equals: .language)
            } detail: {
                if viewModel.hasUnsupportedLanguageSelection {
                    ConfigurationIssueLabel(
                        message:
                            "The selected provider does not support this language.",
                        warning: true
                    )
                }
            }
        } else {
            ConfigurationSettingRow("Language") {
                Text(viewModel.repairLanguageTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptionModelCatalog:
        [ProviderModelDescriptor]
    {
        viewModel.modelCatalog(
            for: viewModel.transcriptionProviderChoice,
            capability: .transcription
        )
    }

    private var hasTranscriptionModelPickerTag: Bool {
        transcriptionModelCatalog.contains {
            $0.id == viewModel.transcriptionModelChoice
        }
            || (
                viewModel.supportsCustomModels(
                    provider: viewModel.transcriptionProviderChoice,
                    capability: .transcription
                )
                    && viewModel.transcriptionModelChoice
                        == ConfigurationViewModel.customModelChoice
            )
    }

    private func routeIssueFocus() {
        guard let field = viewModel.issues.first?.field else {
            return
        }
        switch field {
        case .transcriptionModel, .language:
            focusedField = field
        default:
            break
        }
    }
}

struct ConfigurationPostProcessingView: View {
    @Bindable var viewModel: ConfigurationViewModel
    @FocusState private var focusedField: ConfigurationField?

    var body: some View {
        ConfigurationPage(
            title: "Post-processing",
            detail: "Optionally clean punctuation and formatting."
        ) {
            ConfigurationSection(
                "Transcript cleanup",
                systemImage: "wand.and.stars"
            ) {
                Toggle(
                    "Enable transcript cleanup",
                    isOn: $viewModel.postProcessingEnabled
                )

                if viewModel.postProcessingEnabled {
                    ConfigurationForm {
                        enabledConfiguration
                    }
                } else {
                    Text(
                        "The raw transcript is inserted without an additional provider request."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: viewModel.issues, initial: true) {
            routeIssueFocus()
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

    @ViewBuilder
    private var enabledConfiguration: some View {
        if let attention = viewModel.postProcessingAttentionMessage {
            ConfigurationIssueLabel(
                message: attention,
                warning: true
            )
        }

        if viewModel.availablePostProcessingProviders.isEmpty {
            ConfigurationNoProviderView(
                viewModel: viewModel,
                capability: .postProcessing
            )
        } else {
            ConfigurationSettingRow("Provider") {
                Picker(
                    "Post-processing provider",
                    selection: Binding(
                        get: {
                            viewModel.postProcessingProviderChoice
                        },
                        set: {
                            viewModel.selectPostProcessingProvider($0)
                        }
                    )
                ) {
                    ForEach(
                        viewModel.availablePostProcessingProviders
                    ) { provider in
                        ConfigurationProviderPickerLabel(
                            descriptor: provider,
                            capability: .postProcessing
                        )
                        .tag(provider.id)
                    }
                }
                .labelsHidden()
                .configurationPickerControl()
            }
        }

        ConfigurationSettingRow("Model") {
            Picker(
                "Post-processing model",
                selection: $viewModel.postProcessingModelChoice
            ) {
                ForEach(
                    viewModel.modelCatalog(
                        for: viewModel.postProcessingProviderChoice,
                        capability: .postProcessing
                    )
                ) { model in
                    ConfigurationModelLabel(model: model)
                        .tag(model.id)
                }
                if
                    viewModel.supportsCustomModels(
                        provider: viewModel.postProcessingProviderChoice,
                        capability: .postProcessing
                    )
                {
                    Divider()
                    Text("Advanced: Custom model")
                        .tag(ConfigurationViewModel.customModelChoice)
                }
            }
            .labelsHidden()
            .configurationPickerControl()
        }

        if
            viewModel.postProcessingModelChoice
                == ConfigurationViewModel.customModelChoice
        {
            ConfigurationSettingRow("Custom model") {
                TextField(
                    "Custom model identifier",
                    text: $viewModel.postProcessingCustomModel
                )
                .textFieldStyle(.roundedBorder)
                .configurationFieldControl()
                .focused(
                    $focusedField,
                    equals: .postProcessingModel
                )
                .accessibilityLabel(
                    "Custom post-processing model identifier"
                )
            }
        }

        if let issue = viewModel.issue(for: .postProcessingModel) {
            ConfigurationFormSupplementary {
                ConfigurationIssueLabel(message: issue.message)
            }
        }

        ConfigurationFormSupplementary {
            ConfigurationStageDisclosure(
                viewModel: viewModel,
                provider: viewModel.postProcessingProviderChoice,
                capability: .postProcessing
            )
        }
    }

    private func routeIssueFocus() {
        guard
            viewModel.issues.first?.field == .postProcessingModel
        else {
            return
        }
        focusedField = .postProcessingModel
    }
}
