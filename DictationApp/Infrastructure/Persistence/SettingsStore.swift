import Foundation

struct StoredSettings {
    var configuration: AppConfiguration
    var hasCompletedFirstRun: Bool
    var globalShortcut: GlobalShortcut
    var holdShortcut: GlobalShortcut?
    var soundCuesEnabled: Bool
    var lastSettingsDestination: String
}

@MainActor
final class SettingsStore {
    private enum Key {
        static let configuration = "v2.configuration"
        static let hasCompletedFirstRun = "v1.hasCompletedFirstRun"
        static let globalShortcut = "v1.globalShortcut"
        static let holdShortcut = "v1.holdShortcut"
        static let soundCuesEnabled = "v1.soundCuesEnabled"
        static let lastSettingsDestination = "v1.lastSettingsDestination"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StoredSettings {
        let configuration: AppConfiguration

        if
            let data = defaults.data(forKey: Key.configuration),
            let decoded = try? decoder.decode(AppConfiguration.self, from: data)
        {
            configuration = OpenAIModelCatalog.migratingCuratedModels(in: decoded)
        } else {
            configuration = .default
        }

        let globalShortcut = loadGlobalShortcut()
        return StoredSettings(
            configuration: configuration,
            hasCompletedFirstRun: defaults.bool(
                forKey: Key.hasCompletedFirstRun
            ),
            globalShortcut: globalShortcut,
            holdShortcut: loadHoldShortcut(toggle: globalShortcut),
            soundCuesEnabled: loadSoundCuesEnabled(),
            lastSettingsDestination:
                defaults.string(forKey: Key.lastSettingsDestination)
                ?? "general"
        )
    }

    func commit(
        configuration: AppConfiguration,
        hasCompletedFirstRun: Bool,
        soundCuesEnabled: Bool,
        globalShortcut: GlobalShortcut,
        holdShortcut: GlobalShortcut?
    ) throws {
        let configurationData = try encoder.encode(configuration)
        let shortcutData = try encoder.encode(globalShortcut)
        let holdShortcutData = try encoder.encode(holdShortcut)
        defaults.set(configurationData, forKey: Key.configuration)
        defaults.set(shortcutData, forKey: Key.globalShortcut)
        defaults.set(holdShortcutData, forKey: Key.holdShortcut)
        defaults.set(
            hasCompletedFirstRun,
            forKey: Key.hasCompletedFirstRun
        )
        defaults.set(
            soundCuesEnabled,
            forKey: Key.soundCuesEnabled
        )
    }

    func saveLastSettingsDestination(_ rawValue: String) {
        defaults.set(rawValue, forKey: Key.lastSettingsDestination)
    }

    private func loadGlobalShortcut() -> GlobalShortcut {
        guard
            let data = defaults.data(forKey: Key.globalShortcut),
            let shortcut = try? decoder.decode(GlobalShortcut.self, from: data),
            shortcut.hasStandardModifier
        else {
            return .defaultShortcut
        }

        return shortcut
    }

    private func loadHoldShortcut(toggle: GlobalShortcut) -> GlobalShortcut? {
        let shortcut: GlobalShortcut?
        if let data = defaults.data(forKey: Key.holdShortcut) {
            shortcut = try? decoder.decode(GlobalShortcut?.self, from: data)
        } else {
            shortcut = .defaultHoldShortcut
        }

        guard let shortcut, shortcut.hasStandardModifier, shortcut != toggle else {
            return nil
        }
        return shortcut
    }

    private func loadSoundCuesEnabled() -> Bool {
        guard defaults.object(forKey: Key.soundCuesEnabled) != nil else {
            return true
        }

        return defaults.bool(forKey: Key.soundCuesEnabled)
    }
}
