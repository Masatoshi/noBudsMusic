import Foundation
import Testing

@testable import NoBudsMusicCore

private func makeDefaults() -> UserDefaults {
    let suite = "noBudsMusic.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("Settings persistence")
struct AppSettingsTests {
    @Test("A fresh install starts from the documented defaults")
    func freshInstallUsesDefaults() {
        let store = UserDefaultsSettingsStore(defaults: makeDefaults())
        #expect(store.load() == AppSettings.default)
        #expect(AppSettings.default.isEnabled)
        #expect(AppSettings.default.showsMenuBarItem)
    }

    @Test("Settings survive a store round trip")
    func roundTrip() {
        let defaults = makeDefaults()
        let saved = AppSettings(
            isEnabled: false,
            showsMenuBarItem: false,
            launchesAtLogin: true
        )
        UserDefaultsSettingsStore(defaults: defaults).save(saved)

        // A separate instance stands in for the next app launch.
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == saved)
    }

    @Test("A missing key does not silently become false")
    func missingKeyKeepsDefault() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SettingsKey.isEnabled)

        let loaded = UserDefaultsSettingsStore(defaults: defaults).load()
        #expect(loaded.isEnabled == false)
        #expect(loaded.showsMenuBarItem == true)
    }
}
