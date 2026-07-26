import Foundation

struct StoredSettings {
    var configuration: AppConfiguration
    var hasCompletedFirstRun: Bool
}

@MainActor
final class SettingsStore {
    private enum Key {
        static let configuration = "v1.configuration"
        static let hasCompletedFirstRun = "v1.hasCompletedFirstRun"
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
            )
        )
    }

    func commit(
        configuration: AppConfiguration,
        hasCompletedFirstRun: Bool
    ) throws {
        let data = try encoder.encode(configuration)
        defaults.set(data, forKey: Key.configuration)
        defaults.set(
            hasCompletedFirstRun,
            forKey: Key.hasCompletedFirstRun
        )
    }
}
