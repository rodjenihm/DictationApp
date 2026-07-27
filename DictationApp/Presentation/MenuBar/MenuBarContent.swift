import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Text(appModel.statusText)

        Divider()

        Button(appModel.primaryActionTitle) {
            appModel.performPrimaryAction()
        }
        .disabled(!appModel.isPrimaryActionEnabled)

        if appModel.canRetryTranscription {
            Button("Retry Transcription") {
                appModel.retryTranscription()
            }
        }

        if appModel.canTranscribePartial {
            Button("Transcribe Partial") {
                appModel.transcribePartial()
            }
        }

        if appModel.canDiscardPartial {
            Button("Discard Partial Recording", role: .destructive) {
                appModel.discardPartial()
            }
        } else if appModel.canDiscardTranscription {
            Button("Discard Recording", role: .destructive) {
                appModel.discardTranscription()
            }
        } else if appModel.canCancel {
            Button("Cancel Dictation") {
                appModel.cancelDictation()
            }
        }

        if appModel.canDismissDeliveryStatus {
            Button("Dismiss") {
                appModel.dismissDeliveryStatus()
            }
        }

        Button(
            appModel.canRepairTranscription
                ? "Repair Transcription Settings"
                : "Open Settings"
        ) {
            appModel.showConfiguration()
        }

        Divider()

        Button("Quit DictationApp") {
            appModel.quit()
        }
        .keyboardShortcut("q")
    }
}
