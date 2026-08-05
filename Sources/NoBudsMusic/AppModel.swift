import Foundation
import NoBudsMusicCore
import Observation
import SwiftUI

/// Owns settings and the diagnostics log, and wires them to the UI.
///
/// Deliberately thin: the decision rule lives in `NoBudsMusicCore.EventFilter`
/// and the mechanism in `NowPlayingSink`. This type only connects them.
@MainActor
@Observable
final class AppModel {
    private let settingsStore: SettingsStoring
    let diagnostics: DiagnosticsLog

    /// The whole mechanism. Absent only in tests.
    private let sink: NowPlayingSink?

    private(set) var settings: AppSettings
    private(set) var recentEvents: [DiagnosticsEntry] = []

    /// Whether the app currently holds the Now Playing destination — the only
    /// thing that suppresses a launch.
    ///
    /// Not always equal to `settings.isEnabled`: a real player takes the
    /// destination back when it starts (`TECH_RESEARCH.md` M17), and the app
    /// does not currently reclaim it afterwards (M18).
    var isHoldingNowPlaying: Bool { sink?.isHoldingDestination ?? false }

    init(
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        diagnostics: DiagnosticsLog? = nil,
        installsSink: Bool = true
    ) {
        let loaded = settingsStore.load()
        let log = diagnostics ?? DiagnosticsLog(isEnabled: loaded.diagnosticsLoggingEnabled)
        self.settingsStore = settingsStore
        self.settings = loaded
        self.diagnostics = log
        self.sink = installsSink ? NowPlayingSink(diagnostics: log) : nil
    }

    // MARK: - Lifecycle

    func start() {
        sink?.onEvent = { [weak self] _ in
            self?.refreshDiagnostics()
        }
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
        settings.isEnabled = enabled
        // Status OFF must release the destination, not merely stop absorbing:
        // holding it while doing nothing would still displace a real player.
        sink?.setEnabled(enabled)
        persist()
    }

    func setShowsMenuBarItem(_ shown: Bool) {
        settings.showsMenuBarItem = shown
        persist()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        settings.launchesAtLogin = LaunchAtLogin.setEnabled(enabled)
        persist()
    }

    func setDiagnosticsLoggingEnabled(_ enabled: Bool) {
        settings.diagnosticsLoggingEnabled = enabled
        diagnostics.setEnabled(enabled)
        persist()
    }

    // MARK: - Diagnostics

    func refreshDiagnostics() {
        recentEvents = diagnostics.recent(limit: 50)
    }

    func clearDiagnostics() {
        diagnostics.clear()
        recentEvents = []
    }

    // MARK: - Internals

    private func persist() {
        settingsStore.save(settings)
    }
}
