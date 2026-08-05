import AppKit
import CoreServices
import NoBudsMusicCore
import SwiftUI
import os

@main
struct NoBudsMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Read through `@AppStorage` rather than from `AppModel`.
    //
    // Measured: reading `@Observable` state from a `Scene` body wedges the main
    // thread in a SwiftUI update loop. `AppModel` remains the only writer; these
    // are views onto the same UserDefaults keys.
    @AppStorage(SettingsKey.isEnabled)
    private var isEnabled = AppSettings.default.isEnabled
    @AppStorage(SettingsKey.showsMenuBarItem)
    private var showsMenuBarItem = AppSettings.default.showsMenuBarItem

    var body: some Scene {
        MenuBarExtra(
            "noBudsMusic",
            // `music.note.square` does not exist; `music.note.tv` is the closest
            // real symbol — a rounded rectangle containing a note. Filled while
            // blocking.
            systemImage: isEnabled ? "music.note.tv.fill" : "music.note.tv",
            isInserted: $showsMenuBarItem
        ) {
            // A ViewBuilder closure: evaluated when the menu opens, not during
            // the scene update. Observable reads are safe here.
            MenuContent(model: appDelegate.model)
        }
    }
}

/// Owns the app model and keeps the process resident with no Dock icon and no
/// windows.
///
/// **The app deliberately has no windows at all.** A window hosting SwiftUI in a
/// `MenuBarExtra`-only app pins the main thread at 100% CPU, looping through
/// `scenesDidChange -> makeMainMenu -> invalidate -> update`. The diagnostics
/// screen that used to live in one is gone; `just logs` replaces it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

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

        // Route 1: another launch that yielded to this instance.
        showObserver = SingleInstance.observeShow { [weak self] in
            Task { @MainActor in self?.showMenuBarItem() }
        }

        // Route 3, registered on the next run loop turn so it lands after
        // SwiftUI has installed its own. Measured: `application(_:open:)` is
        // never delivered to an adaptor delegate under the SwiftUI App
        // lifecycle — SwiftUI consumes the event and routes it to `onOpenURL`
        // on a live View, and this app has none.
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
    ///
    /// Unlike `application(_:open:)`, this one *is* delivered under the SwiftUI
    /// App lifecycle — verified by launching the app twice and reading the log.
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

private struct MenuContent: View {
    // Reads go through `@AppStorage`, never through `AppModel`.
    //
    // Measured, twice: reading `@Observable` state anywhere SwiftUI builds the
    // app's main menu — the scene body *or* the MenuBarExtra content — pins the
    // main thread, looping through `scenesDidChange -> makeMainMenu ->
    // invalidateProperties -> updateViewGraph`. Moving the scene body to
    // `@AppStorage` fixed one trigger and left this one.
    //
    // Writes still go through `AppModel`, which owns persistence and the sink,
    // and whose setters drop no-op writes. `@AppStorage` then picks the new
    // value up from `UserDefaults`.
    let model: AppModel

    @AppStorage(SettingsKey.isEnabled)
    private var isEnabled = AppSettings.default.isEnabled
    @AppStorage(SettingsKey.showsMenuBarItem)
    private var showsMenuBarItem = AppSettings.default.showsMenuBarItem
    @AppStorage(SettingsKey.launchesAtLogin)
    private var launchesAtLogin = AppSettings.default.launchesAtLogin

    var body: some View {
        Toggle(
            "menu.block",
            isOn: Binding(get: { isEnabled }, set: { model.setEnabled($0) })
        )

        Divider()

        Toggle(
            "menu.showInMenuBar",
            isOn: Binding(
                get: { showsMenuBarItem },
                set: { model.setShowsMenuBarItem($0) }
            )
        )
        .help("help.showInMenuBar")

        Toggle(
            "menu.launchAtLogin",
            isOn: Binding(
                get: { launchesAtLogin },
                set: { model.setLaunchesAtLogin($0) }
            )
        )
        .disabled(!LaunchAtLogin.isSupported)

        Divider()

        Button("menu.quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
