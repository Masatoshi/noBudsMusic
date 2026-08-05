import Foundation

/// Enumerates HID devices.
///
/// Implemented against IOHIDManager in the app target in Phase 2. The protocol
/// exists now so the Devices screen and its merge logic can be built and tested
/// without it.
public protocol HIDDeviceEnumerating: Sendable {
    func connectedDevices() -> [HIDDeviceInfo]
}

/// Phase 1 stand-in: reports nothing connected.
///
/// Not a fallback for a broken enumerator — enumeration is simply not
/// implemented yet, and the Devices screen says so rather than showing an empty
/// list that looks like "no devices attached".
public struct UnavailableDeviceEnumerator: HIDDeviceEnumerating {
    public init() {}

    public func connectedDevices() -> [HIDDeviceInfo] { [] }
}

/// Merges saved rules with currently connected devices into what the Devices
/// screen shows.
///
/// A device can be in either set: connected but never configured, or configured
/// but currently disconnected. Both must appear, because a user who unpairs a
/// headset should still be able to see and remove its rule.
public enum DeviceListBuilder {
    public static func build(
        connected: [HIDDeviceInfo],
        rules: [DeviceRule]
    ) -> [DeviceListItem] {
        var rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        var items: [DeviceListItem] = []

        for info in connected {
            let identifier = DeviceIdentifier.make(from: info)
            // A connected device's live properties win over the stored copy:
            // the name or transport may have changed since the rule was saved.
            let existing = rulesByID.removeValue(forKey: identifier.rawValue)
            let rule = DeviceRule(
                identifier: identifier,
                blocksPlayPause: existing?.blocksPlayPause ?? false,
                displayName: info.displayName,
                transport: info.transport
            )
            items.append(DeviceListItem(rule: rule, isConnected: true, info: info))
        }

        for rule in rulesByID.values {
            items.append(DeviceListItem(rule: rule, isConnected: false, info: nil))
        }

        return items.sorted { lhs, rhs in
            // Connected first, then Bluetooth (the only actionable ones), then
            // by name, so the list does not reorder as devices come and go.
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            if lhs.isSelectable != rhs.isSelectable { return lhs.isSelectable }
            return lhs.rule.displayName.localizedStandardCompare(rhs.rule.displayName)
                == .orderedAscending
        }
    }
}
