import Testing

@testable import NoBudsMusicCore

private func buds(
    name: String = "Pixel Buds A-Series",
    transport: DeviceTransport = .bluetooth,
    serial: String? = "SN-1"
) -> HIDDeviceInfo {
    HIDDeviceInfo(
        transport: transport,
        productName: name,
        manufacturer: "Google",
        vendorID: 0x18D1,
        productID: 0x5033,
        serialNumber: serial
    )
}

private func source(_ info: HIDDeviceInfo) -> EventSource {
    .device(DeviceIdentifier.make(from: info), info: info)
}

private func rule(for info: HIDDeviceInfo, blocks: Bool) -> DeviceRule {
    DeviceRule(
        identifier: DeviceIdentifier.make(from: info),
        blocksPlayPause: blocks,
        displayName: info.displayName,
        transport: info.transport
    )
}

@Suite("EventFilter")
struct EventFilterTests {
    let filter = EventFilter()

    @Test("A configured Bluetooth device is blocked when Status is ON")
    func blocksConfiguredBluetoothDevice() {
        let info = buds()
        let outcome = filter.decide(
            key: .play,
            source: source(info),
            rule: rule(for: info, blocks: true),
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .block, reason: .deviceBlocked))
    }

    @Test("Global Status OFF passes everything, rules included")
    func globalStatusOffWins() {
        let info = buds()
        let outcome = filter.decide(
            key: .play,
            source: source(info),
            rule: rule(for: info, blocks: true),
            isEnabled: false
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .statusOff))
    }

    @Test("A Bluetooth device whose rule is off passes")
    func ruleOffPasses() {
        let info = buds()
        let outcome = filter.decide(
            key: .play,
            source: source(info),
            rule: rule(for: info, blocks: false),
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .deviceNotBlocked))
    }

    @Test("An unconfigured Bluetooth device passes")
    func unconfiguredDevicePasses() {
        let outcome = filter.decide(
            key: .play,
            source: source(buds()),
            rule: nil,
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .deviceNotConfigured))
    }

    // The regression that must never ship.
    @Test(
        "Non-Bluetooth devices are never blocked, even with a rule saying otherwise",
        arguments: [DeviceTransport.usb, .builtIn, .other("SPI"), .unknown]
    )
    func nonBluetoothNeverBlocked(transport: DeviceTransport) {
        let info = buds(name: "Magic Keyboard", transport: transport)
        var stored = rule(for: info, blocks: true)
        // Simulate a rule saved while the device looked like Bluetooth, or a
        // hand-edited store.
        stored.transport = transport

        let outcome = filter.decide(
            key: .play,
            source: source(info),
            rule: stored,
            isEnabled: true
        )
        #expect(outcome.decision == .pass)
    }

    // The safety property. If this flips, the app blocks on a guess.
    @Test("An unidentified source fails open")
    func unidentifiedSourceFailsOpen() {
        let outcome = filter.decide(
            key: .play,
            source: .unidentified,
            rule: nil,
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .sourceUnidentified))
    }

    @Test(
        "Only Play/Pause is ever in scope",
        arguments: MediaKey.allCases.filter { $0 != .play }
    )
    func otherKeysAlwaysPass(key: MediaKey) {
        let info = buds()
        let outcome = filter.decide(
            key: key,
            source: source(info),
            rule: rule(for: info, blocks: true),
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .notPlayPause))
    }

    @Test("Volume keys are explicitly out of scope")
    func volumeKeysOutOfScope() {
        for key in [MediaKey.volumeUp, .volumeDown, .mute] {
            #expect(!key.isPlayPause)
        }
    }

    @Test("A rule saved for a different device does not apply")
    func mismatchedRuleIgnored() {
        let connected = buds(name: "Redmi Buds 6 Lite", serial: "SN-A")
        let other = buds(name: "Pixel Buds A-Series", serial: "SN-B")

        let outcome = filter.decide(
            key: .play,
            source: source(connected),
            rule: rule(for: other, blocks: true),
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .deviceNotConfigured))
    }

    @Test("Unmodelled key codes are not classified")
    func unmodelledKeyCodes() {
        #expect(MediaKey.from(rawKeyCode: 99) == nil)
        #expect(MediaKey.from(rawKeyCode: 16) == .play)
    }
}

@Suite("Consumer usage mapping")
struct ConsumerUsageTests {
    @Test(
        "Play, Pause and Play/Pause all map to the Play/Pause key",
        arguments: [0xCD, 0xB0, 0xB1]
    )
    func playFamily(usage: Int) {
        #expect(MediaKey.from(consumerUsage: usage) == .play)
    }

    @Test("Transport keys map without becoming Play/Pause")
    func transportKeys() {
        #expect(MediaKey.from(consumerUsage: 0xB5) == .next)
        #expect(MediaKey.from(consumerUsage: 0xB6) == .previous)
        #expect(MediaKey.from(consumerUsage: 0xB3) == .fastForward)
        #expect(MediaKey.from(consumerUsage: 0xB4) == .rewind)
        for usage in [0xB5, 0xB6, 0xB3, 0xB4] {
            #expect(MediaKey.from(consumerUsage: usage)?.isPlayPause == false)
        }
    }

    @Test("Volume keys map and stay out of scope")
    func volumeKeys() {
        #expect(MediaKey.from(consumerUsage: 0xE9) == .volumeUp)
        #expect(MediaKey.from(consumerUsage: 0xEA) == .volumeDown)
        #expect(MediaKey.from(consumerUsage: 0xE2) == .mute)
        for usage in [0xE9, 0xEA, 0xE2] {
            #expect(MediaKey.from(consumerUsage: usage)?.isPlayPause == false)
        }
    }

    // The Consumer page is mostly display, browser and app-launch controls.
    // Mapping any of those would put unrelated input in front of EventFilter.
    @Test(
        "Unmodelled consumer usages are not classified",
        arguments: [0x00, 0x30, 0x6F, 0x70, 0x223, 0x224, 0x18A]
    )
    func unmodelledUsages(usage: Int) {
        #expect(MediaKey.from(consumerUsage: usage) == nil)
    }

    // The two paths report different numbering for the same physical key.
    @Test("The NX and HID namespaces do not collide")
    func namespacesAreSeparate() {
        // 0x10 is NX_KEYTYPE_PLAY; as a consumer usage it is not a media key.
        #expect(MediaKey.from(rawKeyCode: 0x10) == .play)
        #expect(MediaKey.from(consumerUsage: 0x10) == nil)
        // 0xCD is Play/Pause as a consumer usage; as an NX code it is nothing.
        #expect(MediaKey.from(consumerUsage: 0xCD) == .play)
        #expect(MediaKey.from(rawKeyCode: 0xCD) == nil)
    }
}

@Suite("Now Playing path")
struct NowPlayingFilterTests {
    let filter = EventFilter()

    @Test("Play/Pause is absorbed when Status is ON")
    func absorbsPlayPause() {
        let outcome = filter.decideForNowPlaying(key: .play, isEnabled: true)
        #expect(
            outcome
                == FilterOutcome(decision: .block, reason: .absorbedAsNowPlayingDestination)
        )
    }

    @Test("Status OFF forwards, so a real player keeps the destination")
    func statusOffForwards() {
        let outcome = filter.decideForNowPlaying(key: .play, isEnabled: false)
        #expect(outcome == FilterOutcome(decision: .pass, reason: .statusOff))
    }

    @Test(
        "Nothing but Play/Pause is absorbed, volume included",
        arguments: MediaKey.allCases.filter { $0 != .play }
    )
    func otherKeysForwarded(key: MediaKey) {
        let outcome = filter.decideForNowPlaying(key: key, isEnabled: true)
        #expect(outcome == FilterOutcome(decision: .pass, reason: .notPlayPause))
    }

    // The device-attributed rule must keep refusing to act on an unidentified
    // source. ADR 0003 adds a second contract rather than weakening this one,
    // and this test is what stops the two from being merged later.
    @Test("The device-attributed rule still fails open on an unidentified source")
    func safetyPropertyIntact() {
        let outcome = filter.decide(
            key: .play,
            source: .unidentified,
            rule: nil,
            isEnabled: true
        )
        #expect(outcome == FilterOutcome(decision: .pass, reason: .sourceUnidentified))
    }

    @Test("The Now Playing path counts as blocking, unlike HID")
    func pathCanBlock() {
        #expect(ObservationPath.nowPlaying.canBlock)
        #expect(ObservationPath.eventTap.canBlock)
        #expect(!ObservationPath.hid.canBlock)
    }
}
