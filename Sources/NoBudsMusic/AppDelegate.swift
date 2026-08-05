import AppKit
import CoreServices
import Foundation
import NoBudsMusicCore
import os

/// Keeps the process resident with no Dock icon and no windows.
///
/// **The app has no windows at all**, and no SwiftUI. Diagnostics live in
/// `just logs`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: StatusItemController?

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "app")
    private var showObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would fight this one for the Now Playing destination.
        if SingleInstance.yieldToExistingInstance() {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        model.start()

        let statusItem = StatusItemController(model: model)
        self.statusItem = statusItem
        model.onSettingsChanged = { [weak statusItem] in
            statusItem?.refresh()
        }

        // Route 1: another launch that yielded to this instance.
        showObserver = SingleInstance.observeShow { [weak self] in
            Task { @MainActor in self?.showMenuBarItem() }
        }

        // Route 3. Registered on the next run loop turn purely out of caution;
        // the SwiftUI proxy that used to consume this event is gone.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAppleEventManager.shared().setEventHandler(
                self,
                andSelector: #selector(handleGetURL(_:withReply:)),
                forEventClass: AEEventClass(kInternetEventClass),
                andEventID: AEEventID(kAEGetURL)
            )
        }

        logger.info("launched")
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReply reply: NSAppleEventDescriptor
    ) {
        let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue
        guard let raw, URL(string: raw)?.scheme == AppIdentity.urlScheme else { return }
        showMenuBarItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let showObserver {
            DistributedNotificationCenter.default().removeObserver(showObserver)
        }
        model.stop()
    }

    /// Route 2: Finder or Spotlight re-launching the running instance.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMenuBarItem()
        return false
    }

    /// The only way back once the menu bar item is hidden. With no windows,
    /// re-showing the item *is* the recovery path.
    private func showMenuBarItem() {
        logger.info("showing the menu bar item")
        model.setShowsMenuBarItem(true)
    }
}
