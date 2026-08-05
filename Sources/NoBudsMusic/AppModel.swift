import Foundation
import NoBudsMusicCore
import Observation

/// Owns settings and the sink.
///
/// Deliberately thin: the decision rule lives in `NoBudsMusicCore.EventFilter`
/// and the mechanism in `NowPlayingSink`.
@MainActor
@Observable
final class AppModel {
    private let settingsStore: SettingsStoring
    private let sink: NowPlayingSink?

    private(set) var settings: AppSettings

    init(settingsStore: SettingsStoring = UserDefaultsSettingsStore(), installsSink: Bool = true) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.sink = installsSink ? NowPlayingSink() : nil
    }

    // MARK: - Lifecycle

    func start() {
        sink?.setEnabled(settings.isEnabled)

        // The system truth wins over the persisted value: the user can revoke
        // the login item outside the app.
        if LaunchAtLogin.isSupported {
            settings.launchesAtLogin = LaunchAtLogin.isEnabled
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
        persist()
    }

    /// The guard is load-bearing, not an optimisation.
    ///
    /// `MenuBarExtra(isInserted:)` writes back to its binding on every scene
    /// update. Without this check that write reaches `UserDefaults`, which
    /// notifies the `@AppStorage` the scene reads, which re-evaluates the
    /// scene, which writes again — measured as a sustained 100% CPU spin on the
    /// main thread. An unchanged value must not touch storage.
    func setShowsMenuBarItem(_ shown: Bool) {
        guard settings.showsMenuBarItem != shown else { return }
        settings.showsMenuBarItem = shown
        persist()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        let result = LaunchAtLogin.setEnabled(enabled)
        guard settings.launchesAtLogin != result else { return }
        settings.launchesAtLogin = result
        persist()
    }

    private func persist() {
        settingsStore.save(settings)
    }
}
