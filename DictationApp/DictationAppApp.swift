//
//  DictationAppApp.swift
//  DictationApp
//
//  Created by Danijel Mitrović on 26. 7. 2026..
//

import SwiftUI

@main
struct DictationAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("DictationApp", systemImage: "waveform.badge.mic") {
            MenuBarContent(appModel: appDelegate.appModel)
        }
    }
}
