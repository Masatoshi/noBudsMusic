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
        #expect(AppSettings.default.diagnosticsLoggingEnabled)
    }

    @Test("Settings survive a store round trip")
    func roundTrip() {
        let defaults = makeDefaults()
        let saved = AppSettings(
            isEnabled: false,
            showsMenuBarItem: false,
            launchesAtLogin: true,
            diagnosticsLoggingEnabled: false
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
        #expect(loaded.diagnosticsLoggingEnabled == true)
    }
}

@Suite("DiagnosticsLog")
struct DiagnosticsLogTests {
    private func entry() -> DiagnosticsEntry {
        DiagnosticsEntry(
            key: .play,
            outcome: FilterOutcome(decision: .pass, reason: .statusOff)
        )
    }

    @Test("The log is bounded")
    func boundedLog() {
        let log = DiagnosticsLog(capacity: 3)
        for _ in 0..<10 { log.append(entry()) }
        #expect(log.recent(limit: 100).count == 3)
    }

    @Test("Disabling logging stops recording")
    func disabledStopsRecording() {
        let log = DiagnosticsLog(isEnabled: false)
        log.append(entry())
        #expect(log.recent().isEmpty)

        log.setEnabled(true)
        log.append(entry())
        #expect(log.recent().count == 1)
    }

    @Test("Recent returns newest first")
    func newestFirst() {
        let log = DiagnosticsLog()
        let first = entry()
        let second = entry()
        log.append(first)
        log.append(second)
        #expect(log.recent().map(\.id) == [second.id, first.id])
    }
}
