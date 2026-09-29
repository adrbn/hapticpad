import Foundation
import HapticPadCore
import os

/// Persists settings as JSON in the app's user defaults.
struct SettingsStore {
    /// Starts from the defaults and keeps nothing, so snapshots never show or touch the user's settings.
    static var ephemeral: SettingsStore { SettingsStore(defaults: nil) }

    private static let key = "settings.v1"
    private let defaults: UserDefaults?
    private let log = Logger(subsystem: "HapticPad", category: "settings")

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    func load() -> Settings {
        guard let data = defaults?.data(forKey: Self.key) else { return .default }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            log.error("Stored settings were unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            return .default
        }
    }

    func save(_ settings: Settings) {
        guard let defaults else { return }
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            log.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
