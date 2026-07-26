import Foundation

struct StoredSettings {
    var configuration: AppConfiguration
    var hasCompletedFirstRun: Bool
    var globalShortcut: GlobalShortcut
    var soundCuesEnabled: Bool
}

@MainActor
final class SettingsStore {
    private enum Key {
        static let configuration = "v1.configuration"
        static let hasCompletedFirstRun = "v1.hasCompletedFirstRun"
        static let globalShortcut = "v1.globalShortcut"
        static let soundCuesEnabled = "v1.soundCuesEnabled"
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
            configuration = decoded
        } else {
            configuration = .default
        }

        return StoredSettings(
            configuration: configuration,
            hasCompletedFirstRun: defaults.bool(
                forKey: Key.hasCompletedFirstRun
            ),
            globalShortcut: loadGlobalShortcut(),
            soundCuesEnabled: loadSoundCuesEnabled()
        )
    }

    func commit(
        configuration: AppConfiguration,
        hasCompletedFirstRun: Bool,
        soundCuesEnabled: Bool
    ) throws {
        let data = try encoder.encode(configuration)
        defaults.set(data, forKey: Key.configuration)
        defaults.set(
            hasCompletedFirstRun,
            forKey: Key.hasCompletedFirstRun
        )
        defaults.set(
            soundCuesEnabled,
            forKey: Key.soundCuesEnabled
        )
    }

    func commit(globalShortcut: GlobalShortcut) throws {
        let data = try encoder.encode(globalShortcut)
        defaults.set(data, forKey: Key.globalShortcut)
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

    private func loadSoundCuesEnabled() -> Bool {
        guard defaults.object(forKey: Key.soundCuesEnabled) != nil else {
            return true
        }

        return defaults.bool(forKey: Key.soundCuesEnabled)
    }
}
