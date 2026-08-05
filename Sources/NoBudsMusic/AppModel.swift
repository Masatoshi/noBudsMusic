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
    private let audio: AudioActivityMonitor?

    private(set) var settings: AppSettings

    /// Called after any setting changes, so the menu bar item can update.
    var onSettingsChanged: (@MainActor () -> Void)?

    init(settingsStore: SettingsStoring = UserDefaultsSettingsStore(), installsSink: Bool = true) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.sink = installsSink ? NowPlayingSink() : nil
        self.audio = installsSink ? AudioActivityMonitor() : nil
    }

    var isHoldingDestination: Bool { sink?.isHoldingDestination ?? false }

    // MARK: - Lifecycle

    func start() {
        audio?.onChange = { [weak self] _ in
            Task { @MainActor in self?.syncSink() }
        }
        audio?.start()
        syncSink()

        // The system truth wins over the persisted value: the user can revoke
        // the login item outside the app.
        if LaunchAtLogin.isSupported, settings.launchesAtLogin != LaunchAtLogin.isEnabled {
            settings.launchesAtLogin = LaunchAtLogin.isEnabled
            settingsStore.save(settings)
        }
    }

    func stop() {
        audio?.stop()
        sink?.deactivate()
    }

    /// The sink holds the Now Playing destination only while the app is enabled
    /// *and* nothing else is playing audio.
    ///
    /// That second condition is the whole design. Declaring `.playing`
    /// unconditionally steals the destination from real players (M19);
    /// declaring `.paused` never wins it at all (M21). Holding `.playing` only
    /// during silence gets both halves right, because the bug can only happen
    /// during silence in the first place.
    private func syncSink() {
        let isPlaying = audio?.isAudioPlaying ?? false
        sink?.setEnabled(settings.isEnabled && !isPlaying)
    }

    // MARK: - Menu actions

    func setEnabled(_ enabled: Bool) {
        guard settings.isEnabled != enabled else { return }
        settings.isEnabled = enabled
        // Off must release the destination, not merely stop absorbing: holding
        // it while doing nothing would still displace a real player.
        syncSink()
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
