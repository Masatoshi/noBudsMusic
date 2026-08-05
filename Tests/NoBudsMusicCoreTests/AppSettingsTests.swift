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

@Suite("DeviceRuleStore")
struct DeviceRuleStoreTests {
    private func rule(_ name: String, blocks: Bool = true) -> DeviceRule {
        DeviceRule(
            identifier: DeviceIdentifier(rawValue: "s:\(name)", tier: .serial),
            blocksPlayPause: blocks,
            displayName: name,
            transport: .bluetooth
        )
    }

    @Test("Rules survive a store round trip")
    func roundTrip() {
        let defaults = makeDefaults()
        let store = UserDefaultsDeviceRuleStore(defaults: defaults)
        store.upsert(rule("Pixel Buds A-Series"))
        store.upsert(rule("Redmi Buds 6 Lite", blocks: false))

        let reloaded = UserDefaultsDeviceRuleStore(defaults: defaults)
        #expect(reloaded.allRules().count == 2)
        #expect(
            reloaded.rule(for: DeviceIdentifier(rawValue: "s:Pixel Buds A-Series", tier: .serial))?
                .blocksPlayPause == true
        )
    }

    @Test("Upsert replaces rather than duplicates")
    func upsertReplaces() {
        let store = UserDefaultsDeviceRuleStore(defaults: makeDefaults())
        store.upsert(rule("Pixel Buds A-Series", blocks: true))
        store.upsert(rule("Pixel Buds A-Series", blocks: false))

        #expect(store.allRules().count == 1)
        #expect(store.allRules()[0].blocksPlayPause == false)
    }

    @Test("Removing a rule removes it from the reloaded store")
    func removePersists() {
        let defaults = makeDefaults()
        let store = UserDefaultsDeviceRuleStore(defaults: defaults)
        store.upsert(rule("Pixel Buds A-Series"))
        store.remove(DeviceIdentifier(rawValue: "s:Pixel Buds A-Series", tier: .serial))

        #expect(UserDefaultsDeviceRuleStore(defaults: defaults).allRules().isEmpty)
    }

    // Losing rules is bad; refusing to start is worse. Nothing is blocked by
    // default, so an empty set is the safe failure.
    @Test("Corrupt stored data yields no rules rather than a crash")
    func corruptDataIsSurvivable() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsDeviceRuleStore.defaultsKey)

        #expect(UserDefaultsDeviceRuleStore(defaults: defaults).allRules().isEmpty)
    }

    @Test("A rule for a non-Bluetooth device is never effective")
    func nonBluetoothRuleIneffective() {
        let usbRule = DeviceRule(
            identifier: DeviceIdentifier(rawValue: "s:kbd", tier: .serial),
            blocksPlayPause: true,
            displayName: "Magic Keyboard",
            transport: .usb
        )
        #expect(!usbRule.isEffective)
    }
}

@Suite("DiagnosticsLog")
struct DiagnosticsLogTests {
    private func entry() -> DiagnosticsEntry {
        DiagnosticsEntry(
            key: .play,
            source: .unidentified,
            outcome: FilterOutcome(decision: .pass, reason: .sourceUnidentified),
            path: .hid
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

    // The HID path cannot consume an event, so a blocking decision observed
    // there did not actually block anything. Reporting otherwise would make the
    // Phase 3 comparison meaningless.
    @Test("A blocking outcome on the HID path is not a block")
    func hidPathCannotBlock() {
        let entry = DiagnosticsEntry(
            key: .play,
            source: .unidentified,
            outcome: FilterOutcome(decision: .block, reason: .deviceBlocked),
            path: .hid
        )
        #expect(entry.outcome.isBlocked)
        #expect(!entry.wasBlocked)
        #expect(!ObservationPath.hid.canBlock)
        #expect(ObservationPath.eventTap.canBlock)
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
