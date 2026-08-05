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
    // thread. SwiftUI's scene update rebuilds the main menu, which invalidates
    // the same graph that read the state, and the run loop never completes a
    // turn — no timers, no dispatched blocks, no Apple Events, no further
    // delegate callbacks. The app looks alive because the menu bar item is
    // already installed.
    //
    // `AppModel` remains the only writer; these are views onto the same
    // UserDefaults keys and update when it persists.
    @AppStorage(SettingsKey.isEnabled)
    private var isEnabled = AppSettings.default.isEnabled
    @AppStorage(SettingsKey.showsMenuBarItem)
    private var showsMenuBarItem = AppSettings.default.showsMenuBarItem

    var body: some Scene {
        MenuBarExtra(
            "noBudsMusic",
            // `music.note.square` does not exist; `music.note.tv` is the
            // closest real symbol — a rounded rectangle containing a note.
            // Filled while the sink is holding the destination.
            systemImage: isEnabled ? "music.note.tv.fill" : "music.note.tv",
            isInserted: $showsMenuBarItem
        ) {
            // A ViewBuilder closure: evaluated when the menu opens, not during
            // the scene update. Observable reads are safe here.
            MenuContent(model: appDelegate.model, windows: appDelegate.settingsWindow)
        }
    }
}

/// Owns the app model and keeps the process resident with no Dock icon and no
/// windows.
///
/// The model lives here rather than in `@State` so it can be started from
/// `applicationDidFinishLaunching`, which runs whether or not the menu has ever
/// been opened — and still runs when the menu bar item is hidden.
///
/// Not an `ObservableObject`, and `settingsWindow` is not `lazy`: both would put
/// mutation of an observed object on the scene-update path.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let settingsWindow: SettingsWindowController

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "app")
    private var showSettingsObserver: NSObjectProtocol?

    override init() {
        let model = AppModel()
        self.model = model
        self.settingsWindow = SettingsWindowController(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would fight this one for the Now Playing destination.
        if SingleInstance.yieldToExistingInstance() {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        model.start()

        // Route 1: another launch that yielded to this instance.
        showSettingsObserver = SingleInstance.observeShowSettings { [weak self] in
            Task { @MainActor in self?.showSettings() }
        }

        // Route 3, registered on the next run loop turn so it lands after
        // SwiftUI has installed its own. Measured: `application(_:open:)` is
        // never delivered to an adaptor delegate under the SwiftUI App
        // lifecycle — SwiftUI consumes the event and routes it to `onOpenURL`
        // on a live View, and this app has none while the menu is closed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAppleEventManager.shared().setEventHandler(
                self,
                andSelector: #selector(handleGetURL(_:withReply:)),
                forEventClass: AEEventClass(kInternetEventClass),
                andEventID: AEEventID(kAEGetURL)
            )
            self.logger.info("url handler registered")
        }

        logger.info("launched")
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReply reply: NSAppleEventDescriptor
    ) {
        let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue
        guard let raw, URL(string: raw)?.scheme == AppIdentity.urlScheme else { return }
        showSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let showSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(showSettingsObserver)
        }
    }

    /// Route 2: Finder or Spotlight re-launching the running instance.
    ///
    /// Unlike `application(_:open:)`, this one *is* delivered under the SwiftUI
    /// App lifecycle — verified by launching the app twice and reading the log.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    private func showSettings() {
        logger.info("showing settings window")
        settingsWindow.show(tab: .diagnostics)
    }
}

private struct MenuContent: View {
    // Not `@Bindable`: every mutation goes through an explicit `AppModel` method
    // so persistence and the event path stay in sync.
    let model: AppModel
    let windows: SettingsWindowController

    var body: some View {
        Toggle(
            "Status",
            isOn: Binding(get: { model.settings.isEnabled }, set: { model.setEnabled($0) })
        )

        Divider()

        Toggle(
            "Show in Menu Bar",
            isOn: Binding(
                get: { model.settings.showsMenuBarItem },
                set: { model.setShowsMenuBarItem($0) }
            )
        )
        .help("非表示にしても常駐は続きます。アプリを再度開くと戻ります。")

        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { model.settings.launchesAtLogin },
                set: { model.setLaunchesAtLogin($0) }
            )
        )
        .disabled(!LaunchAtLogin.isSupported)

        Button("Diagnostics...") { windows.show(tab: .diagnostics) }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
