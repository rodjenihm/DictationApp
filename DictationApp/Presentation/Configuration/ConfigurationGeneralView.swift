import SwiftUI

struct ConfigurationGeneralView: View {
    @Bindable var viewModel: ConfigurationViewModel

    var body: some View {
        ConfigurationPage(
            title: "General",
            detail: "Permissions, shortcut, feedback, and privacy behavior."
        ) {
            permissionsSection
            recordingSection
            shortcutSection
            feedbackSection
            privacySection
        }
    }

    private var recordingSection: some View {
        ConfigurationSettingsGroup(
            "Recording",
            systemImage: "mic"
        ) {
            LabeledContent("Microphone") {
                Picker(
                    "Microphone",
                    selection: $viewModel.audioInputSelection
                ) {
                    Text("System Default")
                        .tag(AudioInputPreference.Identity.systemDefault)

                    ForEach(viewModel.availableAudioInputDevices) {
                        device in
                        Text(device.name)
                            .tag(
                                viewModel.audioInputPreference(
                                    for: device
                                ).identity
                            )
                    }

                    if shouldShowUnavailablePreference {
                        Text(
                            "\(viewModel.audioInputDisplayName(for: viewModel.audioInputPreference)) — Unavailable"
                        )
                        .tag(viewModel.audioInputPreference.identity)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                .accessibilityLabel("Microphone")
                .accessibilityValue(
                    viewModel.audioInputDisplayName(
                        for: viewModel.audioInputPreference
                    )
                )
            }

            Text(viewModel.audioInputPreferenceStatusMessage)
                .font(.caption)
                .foregroundStyle(
                    viewModel.isAudioInputPreferenceAvailable
                        ? Color.secondary
                        : Color.orange
                )
        }
    }

    private var shouldShowUnavailablePreference: Bool {
        !viewModel.isAudioInputPreferenceAvailable
            && viewModel.audioInputPreference != .systemDefault
            && !viewModel.availableAudioInputDevices.contains {
                viewModel.audioInputPreference(for: $0)
                    .identity == viewModel.audioInputPreference.identity
            }
    }

    private var permissionsSection: some View {
        ConfigurationSettingsGroup(
            "Permissions",
            systemImage: "hand.raised"
        ) {
            LabeledContent("Microphone") {
                HStack(spacing: 10) {
                    ConfigurationPermissionStatusLabel(
                        title: microphoneStatusTitle,
                        granted: viewModel.microphoneStatus == .granted
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
                    ConfigurationPermissionStatusLabel(
                        title: accessibilityStatusTitle,
                        granted: viewModel.accessibilityStatus == .granted
                    )
                    accessibilityAction
                }
            }

            Text(
                "Accessibility enables automatic insertion. Dictation remains available through the clipboard without it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            LabeledContent("Speech Recognition") {
                HStack(spacing: 10) {
                    ConfigurationPermissionStatusLabel(
                        title: speechRecognitionStatusTitle,
                        granted:
                            viewModel.speechRecognitionStatus
                                == .granted
                    )
                    speechRecognitionAction
                }
            }

            Text(
                "Speech Recognition is used only for Apple On-Device transcription. It is not requested when OpenAI is used."
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

    @ViewBuilder
    private var speechRecognitionAction: some View {
        switch viewModel.speechRecognitionStatus {
        case .notDetermined:
            AccessibleActionButton(
                title: "Enable",
                accessibilityLabel:
                    "Enable Speech Recognition access",
                accessibilityHelp:
                    "Requests permission from macOS for Apple On-Device transcription."
            ) {
                Task {
                    await viewModel.enableSpeechRecognition()
                }
            }
        case .denied, .restricted:
            AccessibleActionButton(
                title: "Open System Settings",
                accessibilityLabel:
                    "Open Speech Recognition settings",
                accessibilityHelp:
                    "Opens the macOS Speech Recognition privacy settings."
            ) {
                viewModel.openSpeechRecognitionSettings()
            }
        case .granted:
            EmptyView()
        }
    }

    private var shortcutSection: some View {
        ConfigurationSettingsGroup(
            "Global Shortcut",
            systemImage: "keyboard"
        ) {
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
                ConfigurationIssueLabel(message: message)
            }
        }
    }

    private var feedbackSection: some View {
        ConfigurationSettingsGroup(
            "Feedback",
            systemImage: "speaker.wave.2"
        ) {
            Toggle(
                "Play start, stop, cancel, and failure sounds",
                isOn: $viewModel.soundCuesEnabled
            )
        }
    }

    private var privacySection: some View {
        ConfigurationSettingsGroup(
            "Data & Privacy",
            systemImage: "lock.shield"
        ) {
            Label(
                "Provider credentials are stored in macOS Keychain.",
                systemImage: "key.fill"
            )
            ConfigurationStageDisclosure(
                viewModel: viewModel,
                provider: viewModel.transcriptionProviderChoice,
                capability: .transcription,
                compact: false
            )
            if viewModel.postProcessingEnabled {
                ConfigurationStageDisclosure(
                    viewModel: viewModel,
                    provider: viewModel.postProcessingProviderChoice,
                    capability: .postProcessing,
                    compact: false
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
            "DictationApp can record from the microphone selected below."
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

    private var speechRecognitionStatusTitle: String {
        switch viewModel.speechRecognitionStatus {
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
}
