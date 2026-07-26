import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Text(appModel.statusText)

        Divider()

        Button("Start Dictation") {}
            .disabled(true)

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
