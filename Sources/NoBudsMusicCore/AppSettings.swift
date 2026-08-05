import Foundation

/// User-visible settings, mirroring the menu bar items.
///
/// Named `AppSettings` rather than `Settings` because `SwiftUI.Settings` is a
/// scene type and the bare name is ambiguous in the app target.
public struct AppSettings: Sendable, Equatable {
    /// Whether the app holds the Now Playing destination and discards
    /// Play/Pause. Off means it releases the destination entirely.
    public var isEnabled: Bool
    /// Whether the menu bar item is shown. The app keeps running when hidden.
    public var showsMenuBarItem: Bool
    /// Launch at login (SMAppService).
    public var launchesAtLogin: Bool

    public static let `default` = AppSettings(
        isEnabled: true,
        showsMenuBarItem: true,
        launchesAtLogin: false
    )

    public init(isEnabled: Bool, showsMenuBarItem: Bool, launchesAtLogin: Bool) {
        self.isEnabled = isEnabled
        self.showsMenuBarItem = showsMenuBarItem
        self.launchesAtLogin = launchesAtLogin
    }
}

public protocol SettingsStoring: AnyObject, Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// Keys are namespaced so a future migration can find them.
public enum SettingsKey {
    public static let isEnabled = "noBudsMusic.isEnabled"
    public static let showsMenuBarItem = "noBudsMusic.showsMenuBarItem"
    public static let launchesAtLogin = "noBudsMusic.launchesAtLogin"
}

public final class UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        AppSettings(
            isEnabled: value(for: SettingsKey.isEnabled, default: AppSettings.default.isEnabled),
            showsMenuBarItem: value(
                for: SettingsKey.showsMenuBarItem,
                default: AppSettings.default.showsMenuBarItem
            ),
            launchesAtLogin: value(
                for: SettingsKey.launchesAtLogin,
                default: AppSettings.default.launchesAtLogin
            )
        )
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.isEnabled, forKey: SettingsKey.isEnabled)
        defaults.set(settings.showsMenuBarItem, forKey: SettingsKey.showsMenuBarItem)
        defaults.set(settings.launchesAtLogin, forKey: SettingsKey.launchesAtLogin)
    }

    /// `UserDefaults.bool(forKey:)` returns `false` for a missing key, which
    /// would silently flip defaults that should start as `true`.
    private func value(for key: String, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}

/// Test double.
public final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings

    public init(settings: AppSettings = .default) {
        self.settings = settings
    }

    public func load() -> AppSettings {
        lock.withLock { settings }
    }

    public func save(_ settings: AppSettings) {
        lock.withLock { self.settings = settings }
    }
}
