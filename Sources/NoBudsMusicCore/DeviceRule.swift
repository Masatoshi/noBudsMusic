import Foundation

/// Per-device blocking setting.
///
/// A rule outlives the device's connection: the Devices screen has to show a
/// disconnected headset with its setting intact, so the display name is stored
/// alongside the identifier rather than looked up live.
public struct DeviceRule: Sendable, Equatable, Codable, Identifiable {
    public let identifier: DeviceIdentifier
    public var blocksPlayPause: Bool
    /// Last observed name, for the UI when the device is not connected.
    public var displayName: String
    /// Last observed transport. Persisted so a saved rule can be shown as
    /// Bluetooth without the device being present.
    public var transport: DeviceTransport

    public var id: String { identifier.rawValue }

    public init(
        identifier: DeviceIdentifier,
        blocksPlayPause: Bool,
        displayName: String,
        transport: DeviceTransport
    ) {
        self.identifier = identifier
        self.blocksPlayPause = blocksPlayPause
        self.displayName = displayName
        self.transport = transport
    }

    /// Only Bluetooth devices may be blocked. A rule that says otherwise is
    /// treated as off regardless of what is stored, so a hand-edited plist or a
    /// device that changed transport cannot silently start eating keyboard
    /// input.
    public var isEffective: Bool {
        blocksPlayPause && transport.isBluetooth
    }
}

/// A device the user may configure: the rule, plus whether it is present now.
public struct DeviceListItem: Sendable, Equatable, Identifiable {
    public let rule: DeviceRule
    public let isConnected: Bool
    /// Present only while connected.
    public let info: HIDDeviceInfo?

    public var id: String { rule.id }

    public init(rule: DeviceRule, isConnected: Bool, info: HIDDeviceInfo?) {
        self.rule = rule
        self.isConnected = isConnected
        self.info = info
    }

    /// Non-Bluetooth devices are listed for diagnosis but cannot be selected.
    public var isSelectable: Bool {
        rule.transport.isBluetooth
    }
}
