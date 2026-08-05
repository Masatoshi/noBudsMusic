import AppKit
import NoBudsMusicCore

/// The menu bar item and its menu, in AppKit.
///
/// The menu is rebuilt from `AppModel` each time it is about to open
/// (`menuNeedsUpdate`). That is the whole state-propagation story: no bindings,
/// no observation, no invalidation graph — which is precisely why this replaced
/// the SwiftUI `MenuBarExtra`.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    /// Reflects current settings in the button and visibility.
    func refresh() {
        statusItem.isVisible = model.settings.showsMenuBarItem

        // A plain single note, in both states. `music.note.slash` exists but
        // reads as "music is blocked", which is the opposite of what the off
        // state means here — the app is doing nothing when off. Dimming is
        // unambiguous and keeps the icon to one glyph.
        statusItem.button?.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "noBudsMusic"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.appearsDisabled = !model.settings.isEnabled
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let mainItem = toggle(
            title: NSLocalizedString("menu.block", comment: "Main toggle"),
            isOn: model.settings.isEnabled,
            action: #selector(toggleEnabled)
        )
        mainItem.toolTip = NSLocalizedString("help.block", comment: "What the app does")
        menu.addItem(mainItem)

        menu.addItem(.separator())

        let showItem = toggle(
            title: NSLocalizedString("menu.showInMenuBar", comment: "Menu bar visibility"),
            isOn: model.settings.showsMenuBarItem,
            action: #selector(toggleShowsMenuBarItem)
        )
        showItem.toolTip = NSLocalizedString("help.showInMenuBar", comment: "Recovery hint")
        menu.addItem(showItem)

        let loginItem = toggle(
            title: NSLocalizedString("menu.launchAtLogin", comment: "Login item"),
            isOn: model.settings.launchesAtLogin,
            action: #selector(toggleLaunchAtLogin)
        )
        loginItem.isEnabled = LaunchAtLogin.isSupported
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: "Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    private func toggle(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        model.setEnabled(!model.settings.isEnabled)
    }

    @objc private func toggleShowsMenuBarItem() {
        model.setShowsMenuBarItem(!model.settings.showsMenuBarItem)
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchesAtLogin(!model.settings.launchesAtLogin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
