import Foundation
import NoBudsMusicCore

/// Owns settings and the sink.
///
/// Deliberately thin: the decision rule lives in `NoBudsMusicCore.EventFilter`
/// and the mechanism in `NowPlayingSink`.
///
/// Not observable. The menu reads current state each time it opens, which is
/// simpler than propagating change notifications and is what removed the last
/// of the SwiftUI update loops.
@MainActor
final class AppModel {
    private let settingsStore: SettingsStoring
    private let sink: NowPlayingSink?

    private(set) var settings: AppSettings

    /// Called after any setting changes, so the menu bar item can update.
    var onSettingsChanged: (@MainActor () -> Void)?

    init(settingsStore: SettingsStoring = UserDefaultsSettingsStore(), installsSink: Bool = true) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.sink = installsSink ? NowPlayingSink() : nil
    }

    var isHoldingDestination: Bool { sink?.isHoldingDestination ?? false }

    // MARK: - Lifecycle

    func start() {
        sink?.setEnabled(settings.isEnabled)

        // The system truth wins over the persisted value: the user can revoke
        // the login item outside the app.
        if LaunchAtLogin.isSupported, settings.launchesAtLogin != LaunchAtLogin.isEnabled {
            settings.launchesAtLogin = LaunchAtLogin.isEnabled
            settingsStore.save(settings)
        }
    }

    func stop() {
        sink?.deactivate()
    }

    // MARK: - Menu actions

    func setEnabled(_ enabled: Bool) {
        guard settings.isEnabled != enabled else { return }
        settings.isEnabled = enabled
        // Off must release the destination, not merely stop absorbing: holding
        // it while doing nothing would still displace a real player.
        sink?.setEnabled(enabled)
        commit()
    }

    func setShowsMenuBarItem(_ shown: Bool) {
        guard settings.showsMenuBarItem != shown else { return }
        settings.showsMenuBarItem = shown
        commit()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        let result = LaunchAtLogin.setEnabled(enabled)
        guard settings.launchesAtLogin != result else { return }
        settings.launchesAtLogin = result
        commit()
    }

    private func commit() {
        settingsStore.save(settings)
        onSettingsChanged?()
    }
}
