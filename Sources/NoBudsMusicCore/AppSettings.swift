import Foundation

/// User-visible settings, mirroring the menu bar items in `README.md`.
///
/// Named `AppSettings` rather than `Settings` because `SwiftUI.Settings` is a
/// scene type and the bare name is ambiguous in the app target.
public struct AppSettings: Sendable, Equatable {
    /// Status ON/OFF. When OFF the app stays resident but suppresses nothing.
    public var isEnabled: Bool
    /// Whether the menu bar item is shown. The app keeps running when hidden.
    public var showsMenuBarItem: Bool
    /// Launch at login (SMAppService).
    public var launchesAtLogin: Bool
    /// Whether observed events are recorded for the Diagnostics screen.
    /// Never affects the blocking decision itself.
    public var diagnosticsLoggingEnabled: Bool

    public static let `default` = AppSettings(
        isEnabled: true,
        showsMenuBarItem: true,
        launchesAtLogin: false,
        diagnosticsLoggingEnabled: true
    )

    public init(
        isEnabled: Bool,
        showsMenuBarItem: Bool,
        launchesAtLogin: Bool,
        diagnosticsLoggingEnabled: Bool
    ) {
        self.isEnabled = isEnabled
        self.showsMenuBarItem = showsMenuBarItem
        self.launchesAtLogin = launchesAtLogin
        self.diagnosticsLoggingEnabled = diagnosticsLoggingEnabled
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
    public static let diagnosticsLoggingEnabled = "noBudsMusic.diagnosticsLoggingEnabled"
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
            ),
            diagnosticsLoggingEnabled: value(
                for: SettingsKey.diagnosticsLoggingEnabled,
                default: AppSettings.default.diagnosticsLoggingEnabled
            )
        )
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.isEnabled, forKey: SettingsKey.isEnabled)
        defaults.set(settings.showsMenuBarItem, forKey: SettingsKey.showsMenuBarItem)
        defaults.set(settings.launchesAtLogin, forKey: SettingsKey.launchesAtLogin)
        defaults.set(
            settings.diagnosticsLoggingEnabled,
            forKey: SettingsKey.diagnosticsLoggingEnabled
        )
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
