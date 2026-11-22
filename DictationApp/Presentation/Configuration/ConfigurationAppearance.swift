import AppKit
import SwiftUI

enum ConfigurationAppearance {
    static let canvas = adaptive(light: 0xF7F7F7, dark: 0x202020)
    static let sidebar = adaptive(light: 0xEEEEEE, dark: 0x181818)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x292929)
    static let border = adaptive(light: 0xDFDFDF, dark: 0x3B3B3B)
    static let highlight = adaptive(light: 0xE9E9E9, dark: 0x343434)
    static let emblem = adaptive(light: 0x505050, dark: 0xCECECE)
    static let success = adaptive(light: 0x21673F, dark: 0x75DCA0)
    static let attention = adaptive(light: 0x875217, dark: 0xF5BB76)
    static let error = adaptive(light: 0xAA293E, dark: 0xFF9CA8)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1
            )
        })
    }
}
