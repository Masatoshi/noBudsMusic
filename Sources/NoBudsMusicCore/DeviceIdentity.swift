import Foundation

/// How a HID device is attached, derived from the IOHID `Transport` property.
///
/// Only `bluetooth` may ever be selected for blocking. Everything else is
/// off-limits by rule, not by policy toggle.
public enum DeviceTransport: Sendable, Equatable, Hashable, Codable {
    case bluetooth
    case usb
    case builtIn
    case other(String)
    case unknown

    /// IOHID reports free-form strings here ("Bluetooth", "BluetoothLowEnergy",
    /// "USB", "SPI", "FIFO", ...), so this matches loosely and keeps the raw
    /// value for anything unrecognised rather than guessing.
    public static func from(raw: String?) -> DeviceTransport {
        guard let raw, !raw.isEmpty else { return .unknown }
        let lowered = raw.lowercased()
        if lowered.contains("bluetooth") { return .bluetooth }
        if lowered.contains("usb") { return .usb }
        if lowered == "spi" || lowered == "fifo" || lowered.contains("built-in") {
            return .builtIn
        }
        return .other(raw)
    }

    public var isBluetooth: Bool { self == .bluetooth }

    public var label: String {
        switch self {
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .builtIn: "Built-in"
        case .other(let raw): raw
        case .unknown: "Unknown"
        }
    }
}

/// The IOHID properties collected for a device, per the implementation brief.
///
/// Every field is optional because IOHID populates them inconsistently across
/// devices — a missing serial number is the normal case for consumer earbuds,
/// not an error.
public struct HIDDeviceInfo: Sendable, Equatable, Hashable {
    public let transport: DeviceTransport
    public let productName: String?
    public let manufacturer: String?
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    /// Collected for diagnostics only. Deliberately excluded from the
    /// identifier: it changes across reconnects and USB port changes.
    public let locationID: Int?
    public let primaryUsagePage: Int?
    public let primaryUsage: Int?

    public init(
        transport: DeviceTransport,
        productName: String? = nil,
        manufacturer: String? = nil,
        vendorID: Int? = nil,
        productID: Int? = nil,
        serialNumber: String? = nil,
        locationID: Int? = nil,
        primaryUsagePage: Int? = nil,
        primaryUsage: Int? = nil
    ) {
        self.transport = transport
        self.productName = productName
        self.manufacturer = manufacturer
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.locationID = locationID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
    }

    public var displayName: String {
        productName ?? manufacturer ?? "Unknown device"
    }
}

/// A stable identifier for a device, plus how confident we are in it.
///
/// Persisted in the rule store, so its string form is a compatibility surface:
/// changing how a tier is composed orphans every saved rule at that tier.
public struct DeviceIdentifier: Sendable, Equatable, Hashable, Codable {
    /// Lower is better. The tier is part of the identity because a device that
    /// starts reporting a serial number must not silently inherit the rule
    /// saved under its weaker identifier.
    public enum Tier: Int, Sendable, Equatable, Hashable, Codable, Comparable {
        /// Vendor + product + serial number. Unique per physical unit.
        case serial = 1
        /// Vendor + product + name. Cannot distinguish two of the same model.
        case vendorProduct = 2
        /// Whatever else is available. Weakest, and easiest to collide.
        case fallback = 3

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let rawValue: String
    public let tier: Tier

    public init(rawValue: String, tier: Tier) {
        self.rawValue = rawValue
        self.tier = tier
    }

    /// True when two physically distinct units could produce this identifier.
    ///
    /// The caller is expected to surface this: the brief requires collision
    /// potential to be stated in the log rather than silently tolerated.
    public var isCollisionProne: Bool {
        tier > .serial
    }

    /// Builds the strongest identifier the available properties support.
    ///
    /// Priority is fixed by the brief: serial first, then vendor/product/name,
    /// then a fallback over the remaining properties.
    public static func make(from info: HIDDeviceInfo) -> DeviceIdentifier {
        let vendor = info.vendorID.map(hex) ?? "-"
        let product = info.productID.map(hex) ?? "-"

        if let serial = info.serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            !serial.isEmpty
        {
            return DeviceIdentifier(rawValue: "s:\(vendor):\(product):\(serial)", tier: .serial)
        }

        if info.vendorID != nil, info.productID != nil,
            let name = info.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        {
            return DeviceIdentifier(
                rawValue: "v:\(vendor):\(product):\(name)", tier: .vendorProduct)
        }

        // Location ID is intentionally absent: including it would produce a new
        // identifier on every reconnect and lose the user's saved rule.
        let parts = [
            info.transport.label,
            info.manufacturer ?? "-",
            info.productName ?? "-",
            vendor,
            product,
            info.primaryUsagePage.map(String.init) ?? "-",
            info.primaryUsage.map(String.init) ?? "-",
        ]
        return DeviceIdentifier(rawValue: "f:" + parts.joined(separator: ":"), tier: .fallback)
    }

    private static func hex(_ value: Int) -> String {
        String(format: "0x%04X", value)
    }
}
