import AppKit
import Foundation
import NoBudsMusicCore
import os

/// Prevents a second copy of the app from running, and gives an already-running
/// instance a way to be told "make yourself visible again".
///
/// Finder and Spotlight normally activate an existing instance rather than
/// launching a second one, which arrives as `applicationShouldHandleReopen`.
/// This handles the cases where that does not apply: a copy launched from a
/// different path, or `open -n`. Without it both instances would claim the Now
/// Playing destination and fight over it.
///
/// The handshake goes through the app's own URL scheme rather than a
/// distributed notification. Both reach the running instance, but a sandboxed
/// app can only post distributed notifications under an app-group-prefixed
/// name, which would mean provisioning an app group for one message. The URL
/// route needs nothing.
enum SingleInstance {
    private static let logger = Logger(
        subsystem: AppIdentity.logSubsystem,
        category: "singleInstance"
    )

    /// Another running copy of this app, if there is one.
    static var otherInstance: NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != current }
    }

    /// Call at launch. Returns `true` when this process should terminate
    /// because another instance already owns the job.
    static func yieldToExistingInstance() -> Bool {
        guard let other = otherInstance else { return false }
        logger.notice(
            """
            another instance is running (pid \(other.processIdentifier, privacy: .public)); \
            asking it to show itself and exiting
            """
        )
        requestShow()
        return true
    }

    /// Asks the running instance to show its menu bar item.
    static func requestShow() {
        guard let url = URL(string: "\(AppIdentity.urlScheme)://show") else { return }
        NSWorkspace.shared.open(url)
    }
}
