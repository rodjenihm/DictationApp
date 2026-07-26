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

        if appModel.canDiscardTranscription {
            Button("Discard Recording", role: .destructive) {
                appModel.discardTranscription()
            }
        } else if appModel.canCancel {
            Button("Cancel Dictation") {
                appModel.cancelDictation()
            }
        }

        Button("Open Settings") {
            appModel.showConfiguration()
        }

        Divider()

        Button("Quit DictationApp") {
            appModel.quit()
        }
        .keyboardShortcut("q")
    }
}
