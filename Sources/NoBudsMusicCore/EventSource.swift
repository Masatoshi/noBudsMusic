import Foundation

/// Which device produced a media key event.
///
/// `unidentified` is a first-class case, not an error. The brief requires that
/// an event whose source cannot be determined is passed through, and the
/// interception layer (`CGEventTap`) carries no device information of its own —
/// so this is the common case, not the exceptional one.
public enum EventSource: Sendable, Equatable {
    case device(DeviceIdentifier, info: HIDDeviceInfo)
    case unidentified

    public var identifier: DeviceIdentifier? {
        if case .device(let id, _) = self { return id }
        return nil
    }

    public var info: HIDDeviceInfo? {
        if case .device(_, let info) = self { return info }
        return nil
    }

    public var transport: DeviceTransport {
        info?.transport ?? .unknown
    }

    public var displayName: String {
        info?.displayName ?? "Unidentified"
    }
}

/// Everything the interception layer can offer about an event, for correlating
/// it back to a device observed elsewhere.
///
/// A `CGEvent` exposes none of the HID device identity, so correlation has to
/// come from a separate IOHID observation. Whether that correlation is reliable
/// enough to act on is the open question in
/// `docs/adr/0001-event-interception-approach.md`.
public struct EventSourceQuery: Sendable, Equatable {
    /// `kCGEventSourceUnixProcessID`. 0 for hardware-generated events.
    public let sourceProcessID: Int64
    /// `kCGEventSourceStateID`.
    public let sourceStateID: Int64
    /// Event timestamp, for correlating with HID reports.
    public let timestamp: UInt64

    public init(sourceProcessID: Int64, sourceStateID: Int64, timestamp: UInt64) {
        self.sourceProcessID = sourceProcessID
        self.sourceStateID = sourceStateID
        self.timestamp = timestamp
    }
}

/// Resolves an event back to the device that produced it.
///
/// Must be callable synchronously and cheaply: the tap callback runs under a
/// system-enforced timeout, and exceeding it disables the tap.
public protocol EventSourceResolving: Sendable {
    func source(for query: EventSourceQuery) -> EventSource
}

/// Never claims to know the source.
///
/// This is what ships until Phase 2 measures whether the event is observable on
/// the HID path at all. With it in place `EventFilter` always passes, so the app
/// observes without changing behaviour.
public struct UnidentifiedSourceResolver: EventSourceResolving {
    public init() {}

    public func source(for query: EventSourceQuery) -> EventSource {
        .unidentified
    }
}
