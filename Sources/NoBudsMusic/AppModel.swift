import Foundation
import NoBudsMusicCore
import os
import Observation
import SwiftUI

/// Owns settings, device rules, and the diagnostics log, and wires them to the
/// UI.
///
/// Deliberately thin: no blocking rules live here (they are in
/// `NoBudsMusicCore.EventFilter`) and no event plumbing (that is
/// `HIDDeviceMonitor` and, from Phase 3, `MediaKeyEventTap`).
@MainActor
@Observable
final class AppModel {
    private let settingsStore: SettingsStoring
    private let ruleStore: DeviceRuleStoring
    let diagnostics: DiagnosticsLog

    /// Phase 2: the HID monitor both enumerates and observes. Injected as one
    /// object because IOHIDManager is one object.
    private let hidMonitor: HIDDeviceMonitor?
    private let enumerator: HIDDeviceEnumerating

    /// The only mechanism that can actually stop the launch. See ADR 0003.
    private let nowPlayingSink: NowPlayingSink?

    private(set) var settings: AppSettings
    private(set) var devices: [DeviceListItem] = []
    private(set) var recentEvents: [DiagnosticsEntry] = []
    private(set) var permissions: PermissionStatus = .unknown

    /// Set when the HID monitor could not start. Surfaced in Diagnostics rather
    /// than swallowed: an empty event list is otherwise indistinguishable from
    /// "the headset produced nothing", which is the exact question Phase 2 is
    /// trying to answer.
    private(set) var monitorError: String?

    /// The event tap is dead: ADR 0001 is Rejected, nothing reaches it. The HID
    /// monitor still runs as an instrument, but it cannot block either.
    let isEventPathActive = false

    /// Whether the app currently holds the Now Playing destination — the only
    /// thing that actually suppresses a launch. See ADR 0003.
    var isHoldingNowPlaying: Bool { nowPlayingSink?.isHoldingDestination ?? false }

    init(
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        ruleStore: DeviceRuleStoring = UserDefaultsDeviceRuleStore(),
        diagnostics: DiagnosticsLog? = nil,
        enumerator: HIDDeviceEnumerating? = nil
    ) {
        let loaded = settingsStore.load()
        let log = diagnostics ?? DiagnosticsLog(isEnabled: loaded.diagnosticsLoggingEnabled)
        self.settingsStore = settingsStore
        self.ruleStore = ruleStore
        self.settings = loaded
        self.diagnostics = log

        if let enumerator {
            // Test seam: no IOHIDManager, no permissions, no run loop.
            self.enumerator = enumerator
            self.hidMonitor = nil
            self.nowPlayingSink = nil
        } else {
            let monitor = HIDDeviceMonitor(
                ruleStore: ruleStore,
                diagnostics: log,
                isEnabled: loaded.isEnabled
            )
            self.enumerator = monitor
            self.hidMonitor = monitor
            self.nowPlayingSink = NowPlayingSink(diagnostics: log)
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Input Monitoring is what makes values arrive at all. Ask before
        // starting so the first launch prompts rather than silently observing
        // nothing.
        Permissions.requestInputMonitoring()
        refreshPermissions()

        hidMonitor?.onEvent = { [weak self] _ in
            Task { @MainActor in self?.refreshDiagnostics() }
        }
        hidMonitor?.onDeviceSetChanged = { [weak self] in
            Task { @MainActor in self?.refreshDevices() }
        }

        do {
            try hidMonitor?.start()
            monitorError = nil
        } catch {
            // Surfaced in Diagnostics *and* logged: a monitor that failed to
            // start is the most likely explanation for an empty event list, and
            // the log is what gets attached to a report.
            monitorError = error.localizedDescription
            Logger(subsystem: AppIdentity.logSubsystem, category: "app")
                .error(
                    "hid monitor failed to start: \(error.localizedDescription, privacy: .public)")
        }

        nowPlayingSink?.onEvent = { [weak self] _ in
            self?.refreshDiagnostics()
        }
        nowPlayingSink?.setEnabled(settings.isEnabled)

        refreshDevices()
        hidMonitor?.logInventory()

        // The system truth wins over the persisted value: the user can revoke
        // the login item outside the app.
        if LaunchAtLogin.isSupported {
            settings.launchesAtLogin = LaunchAtLogin.isEnabled
        }
    }

    func stop() {
        hidMonitor?.stop()
        nowPlayingSink?.deactivate()
    }

    // MARK: - Menu actions

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        hidMonitor?.setEnabled(enabled)
        // Status OFF must release the destination, not merely stop absorbing:
        // holding it while doing nothing would still displace a real player.
        nowPlayingSink?.setEnabled(enabled)
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

    // MARK: - Devices

    func refreshDevices() {
        devices = DeviceListBuilder.build(
            connected: enumerator.connectedDevices(),
            rules: ruleStore.allRules()
        )
    }

    /// Non-Bluetooth devices cannot be blocked; the call is ignored rather than
    /// saving a rule that `EventFilter` would refuse to honour anyway.
    func setBlocking(_ blocks: Bool, for item: DeviceListItem) {
        guard item.isSelectable else { return }
        var rule = item.rule
        rule.blocksPlayPause = blocks
        ruleStore.upsert(rule)
        refreshDevices()
    }

    func removeRule(for item: DeviceListItem) {
        ruleStore.remove(item.rule.identifier)
        refreshDevices()
    }

    // MARK: - Diagnostics

    func refreshDiagnostics() {
        recentEvents = diagnostics.recent(limit: 50)
        refreshPermissions()
    }

    func clearDiagnostics() {
        diagnostics.clear()
        recentEvents = []
    }

    func refreshPermissions() {
        permissions = Permissions.status
    }

    func requestInputMonitoring() {
        Permissions.requestInputMonitoring()
        refreshPermissions()
    }

    func requestAccessibility() {
        Permissions.requestAccessibility()
        refreshPermissions()
    }

    func openInputMonitoringSettings() {
        Permissions.openInputMonitoringSettings()
    }

    func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    // MARK: - Internals

    private func persist() {
        settingsStore.save(settings)
    }
}
