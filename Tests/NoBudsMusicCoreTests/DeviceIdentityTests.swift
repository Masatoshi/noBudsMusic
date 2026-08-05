import Testing

@testable import NoBudsMusicCore

@Suite("DeviceIdentifier")
struct DeviceIdentifierTests {
    @Test("A serial number produces the strongest identifier")
    func serialWins() {
        let info = HIDDeviceInfo(
            transport: .bluetooth,
            productName: "Pixel Buds A-Series",
            vendorID: 0x18D1,
            productID: 0x5033,
            serialNumber: "ABC123"
        )
        let id = DeviceIdentifier.make(from: info)
        #expect(id.tier == .serial)
        #expect(id.rawValue.contains("ABC123"))
        #expect(!id.isCollisionProne)
    }

    @Test("Without a serial number it falls back to vendor + product + name")
    func vendorProductTier() {
        let info = HIDDeviceInfo(
            transport: .bluetooth,
            productName: "Redmi Buds 6 Lite",
            vendorID: 0x2717,
            productID: 0x0042
        )
        let id = DeviceIdentifier.make(from: info)
        #expect(id.tier == .vendorProduct)
        // The brief requires collision potential to be surfaced, so it has to be
        // detectable from the identifier itself.
        #expect(id.isCollisionProne)
    }

    @Test("An empty serial number does not count as a serial number")
    func blankSerialIsIgnored() {
        let info = HIDDeviceInfo(
            transport: .bluetooth,
            productName: "Redmi Buds 6 Lite",
            vendorID: 0x2717,
            productID: 0x0042,
            serialNumber: "   "
        )
        #expect(DeviceIdentifier.make(from: info).tier == .vendorProduct)
    }

    @Test("With neither serial nor vendor/product it falls back")
    func fallbackTier() {
        let info = HIDDeviceInfo(transport: .bluetooth, productName: "Unnamed")
        let id = DeviceIdentifier.make(from: info)
        #expect(id.tier == .fallback)
        #expect(id.isCollisionProne)
    }

    // Location ID changes across reconnects; including it would orphan the
    // user's saved rule every time the headset reconnects.
    @Test("Location ID does not affect the identifier")
    func locationIDExcluded() {
        func info(location: Int) -> HIDDeviceInfo {
            HIDDeviceInfo(
                transport: .bluetooth,
                productName: "Redmi Buds 6 Lite",
                vendorID: 0x2717,
                productID: 0x0042,
                locationID: location
            )
        }
        #expect(
            DeviceIdentifier.make(from: info(location: 1))
                == DeviceIdentifier.make(from: info(location: 2))
        )
    }

    @Test("Two units of the same model without serials collide")
    func sameModelCollides() {
        func unit() -> HIDDeviceInfo {
            HIDDeviceInfo(
                transport: .bluetooth,
                productName: "Redmi Buds 6 Lite",
                vendorID: 0x2717,
                productID: 0x0042
            )
        }
        let a = DeviceIdentifier.make(from: unit())
        let b = DeviceIdentifier.make(from: unit())
        // Documented limitation, asserted so it cannot be forgotten.
        #expect(a == b)
        #expect(a.isCollisionProne)
    }

    @Test("Devices differing only by name are distinct at the vendor/product tier")
    func nameDistinguishes() {
        func info(name: String) -> HIDDeviceInfo {
            HIDDeviceInfo(
                transport: .bluetooth,
                productName: name,
                vendorID: 0x2717,
                productID: 0x0042
            )
        }
        #expect(
            DeviceIdentifier.make(from: info(name: "A"))
                != DeviceIdentifier.make(from: info(name: "B"))
        )
    }
}

@Suite("DeviceTransport")
struct DeviceTransportTests {
    @Test(
        "Bluetooth transports are recognised",
        arguments: ["Bluetooth", "BluetoothLowEnergy", "bluetooth"]
    )
    func bluetoothVariants(raw: String) {
        #expect(DeviceTransport.from(raw: raw).isBluetooth)
    }

    @Test(
        "Non-Bluetooth transports are not",
        arguments: ["USB", "SPI", "FIFO", "Built-in", ""]
    )
    func nonBluetooth(raw: String) {
        #expect(!DeviceTransport.from(raw: raw).isBluetooth)
    }

    @Test("A missing transport is unknown, not assumed")
    func missingTransport() {
        #expect(DeviceTransport.from(raw: nil) == .unknown)
    }

    @Test("An unrecognised transport keeps its raw value")
    func unrecognisedKeepsRaw() {
        #expect(DeviceTransport.from(raw: "I2C") == .other("I2C"))
        #expect(DeviceTransport.from(raw: "I2C").label == "I2C")
    }
}

@Suite("DeviceListBuilder")
struct DeviceListBuilderTests {
    private let earbuds = HIDDeviceInfo(
        transport: .bluetooth,
        productName: "Pixel Buds A-Series",
        vendorID: 0x18D1,
        productID: 0x5033,
        serialNumber: "SN-1"
    )
    private let keyboard = HIDDeviceInfo(
        transport: .usb,
        productName: "Magic Keyboard",
        vendorID: 0x05AC,
        productID: 0x0267,
        serialNumber: "SN-2"
    )

    @Test("A connected device with no rule appears, not blocking")
    func connectedWithoutRule() {
        let items = DeviceListBuilder.build(connected: [earbuds], rules: [])
        #expect(items.count == 1)
        #expect(items[0].isConnected)
        #expect(!items[0].rule.blocksPlayPause)
    }

    @Test("A saved rule survives disconnection")
    func disconnectedRuleShown() {
        let rule = DeviceRule(
            identifier: DeviceIdentifier.make(from: earbuds),
            blocksPlayPause: true,
            displayName: "Pixel Buds A-Series",
            transport: .bluetooth
        )
        let items = DeviceListBuilder.build(connected: [], rules: [rule])
        #expect(items.count == 1)
        #expect(!items[0].isConnected)
        #expect(items[0].rule.blocksPlayPause)
    }

    @Test("A connected device is listed once, keeping its saved setting")
    func mergesRatherThanDuplicates() {
        let rule = DeviceRule(
            identifier: DeviceIdentifier.make(from: earbuds),
            blocksPlayPause: true,
            displayName: "old name",
            transport: .bluetooth
        )
        let items = DeviceListBuilder.build(connected: [earbuds], rules: [rule])
        #expect(items.count == 1)
        #expect(items[0].rule.blocksPlayPause)
        // Live properties win: the name may have changed since the rule was
        // saved.
        #expect(items[0].rule.displayName == "Pixel Buds A-Series")
    }

    @Test("Non-Bluetooth devices are listed but not selectable")
    func keyboardListedNotSelectable() {
        let items = DeviceListBuilder.build(connected: [keyboard], rules: [])
        #expect(items.count == 1)
        #expect(!items[0].isSelectable)
    }

    @Test("Connected and selectable devices sort first")
    func ordering() {
        let disconnected = DeviceRule(
            identifier: DeviceIdentifier(rawValue: "s:x", tier: .serial),
            blocksPlayPause: false,
            displayName: "AAA disconnected",
            transport: .bluetooth
        )
        let items = DeviceListBuilder.build(
            connected: [keyboard, earbuds],
            rules: [disconnected]
        )
        #expect(
            items.map(\.rule.displayName) == [
                "Pixel Buds A-Series", "Magic Keyboard", "AAA disconnected",
            ])
    }
}
