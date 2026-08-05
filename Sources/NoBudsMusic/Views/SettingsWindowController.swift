import AppKit
import SwiftUI

/// The Devices / Diagnostics window.
///
/// Deliberately an AppKit window hosting SwiftUI rather than a SwiftUI `Window`
/// scene: the window has to be openable when the menu bar item is hidden, and a
/// scene reachable only from `MenuBarExtra` content is not. This is the recovery
/// path required by the brief.
@MainActor
final class SettingsWindowController {
    enum Tab: Hashable {
        case diagnostics
    }

    private var window: NSWindow?
    private let model: AppModel
    private var selectedTab: Tab = .diagnostics

    init(model: AppModel) {
        self.model = model
    }

    func show(tab: Tab) {
        selectedTab = tab

        if let window {
            // Rebuild the content so the requested tab is selected; the window
            // itself is reused so its position is preserved.
            window.contentViewController = makeContentViewController()
            present(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "noBudsMusic"
        window.contentViewController = makeContentViewController()
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        // The app runs as an accessory, so it must be activated explicitly or
        // the window opens behind whatever is in front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeContentViewController() -> NSViewController {
        NSHostingController(rootView: SettingsRootView(model: model, initialTab: selectedTab))
    }
}

private struct SettingsRootView: View {
    let model: AppModel

    init(model: AppModel, initialTab: SettingsWindowController.Tab) {
        self.model = model
    }

    // A single screen rather than a TabView: the Devices tab went away with
    // per-device rules (ADR 0003), and a one-tab TabView is just chrome.
    var body: some View {
        DiagnosticsView(model: model)
            .padding()
            .frame(minWidth: 520, minHeight: 320)
    }
}
