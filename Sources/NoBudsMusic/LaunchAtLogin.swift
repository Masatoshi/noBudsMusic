import Foundation
import NoBudsMusicCore
import ServiceManagement
import os

/// Launch at login via `SMAppService.mainApp`.
///
/// Requires a real `.app` bundle: `swift run` produces a bare executable and
/// registration will fail there. Use `just bundle && just open`.
enum LaunchAtLogin {
    private static let logger = Logger(
        subsystem: AppIdentity.logSubsystem,
        category: "launchAtLogin"
    )

    /// `false` when running unbundled, where registration cannot work.
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state. Does not throw: a failed registration is
    /// reported to the caller so the menu can fall back to the real state
    /// instead of showing a checkmark that does not reflect the system.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else {
            logger.error("launch at login unavailable: running without a bundle")
            return false
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("launch at login update failed: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
