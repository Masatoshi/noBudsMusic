import AppKit
import Foundation
import NoBudsMusicCore
import os

/// Prevents a second copy of the app from running, and gives an already-running
/// instance a way to be told "show your settings".
///
/// Finder and Spotlight normally activate an existing instance rather than
/// launching a second one, which arrives as `applicationShouldHandleReopen`.
/// This handles the cases where that does not apply: a copy launched from a
/// different path, or `open -n`. Without it both instances would claim the Now
/// Playing destination and fight over it.
enum SingleInstance {
    /// Posted to the running instance to ask it to surface its UI.
    static let showSettingsNotification = Notification.Name(
        AppIdentity.showSettingsNotificationName)

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
            asking it to show settings and exiting
            """
        )
        requestShowSettings()
        other.activate()
        return true
    }

    /// Asks the running instance to open its settings UI.
    ///
    /// Distributed notifications cross process boundaries; the app is not
    /// sandboxed, so no app-group suffix is needed.
    static func requestShowSettings() {
        DistributedNotificationCenter.default().postNotificationName(
            showSettingsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Observes the request in the instance that stays alive.
    static func observeShowSettings(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: showSettingsNotification,
            object: nil,
            queue: .main
        ) { _ in handler() }
    }
}
