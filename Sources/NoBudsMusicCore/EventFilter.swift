import Foundation

/// What to do with a remote control command.
public enum FilterDecision: String, Sendable, Equatable, Codable {
    /// Let it through, so whatever else wants it can have it.
    case pass
    /// Absorb it. The command stops here and nothing is launched.
    case block
}

/// Why `EventFilter` decided the way it did.
///
/// Surfaced verbatim in the Diagnostics screen: a command that was *not*
/// absorbed has to be explainable, not merely absent from the list.
public enum FilterReason: String, Sendable, Equatable, Codable {
    /// Global Status is OFF, so the app should not be holding the destination
    /// at all.
    case statusOff
    /// Not Play/Pause. Next and Previous are forwarded so the headset's other
    /// gestures keep working.
    case notPlayPause
    /// Absorbed as the Now Playing destination.
    case absorbedAsNowPlayingDestination
}

public struct FilterOutcome: Sendable, Equatable, Codable {
    public let decision: FilterDecision
    public let reason: FilterReason

    public init(decision: FilterDecision, reason: FilterReason) {
        self.decision = decision
        self.reason = reason
    }

    public var isBlocked: Bool { decision == .block }
}

/// The single place that decides whether a command is absorbed.
///
/// **This decision has no device dimension, and cannot have one.** A MediaRemote
/// command carries no device identity: every Bluetooth headset arrives as
/// `com.apple.bluetoothd`, and so does a keyboard media key. There is nothing to
/// attribute — see `TECH_RESEARCH.md` M11 and ADR 0003.
///
/// An earlier version had a second rule that took a source and a per-device
/// rule, and refused to act when the source could not be identified. That rule
/// protected keyboards, and it is gone because the path it protected is gone —
/// not because it was relaxed. What replaces it is narrower and weaker: the app
/// absorbs Play/Pause whenever Status is ON, and the only control over *what* it
/// absorbs is whether it holds the destination at all.
///
/// 1. Status OFF     -> pass.
/// 2. Not Play/Pause -> pass.
/// 3. Otherwise      -> absorb.
public struct EventFilter: Sendable {
    public init() {}

    public func decide(key: MediaKey, isEnabled: Bool) -> FilterOutcome {
        guard isEnabled else {
            return FilterOutcome(decision: .pass, reason: .statusOff)
        }
        guard key.isPlayPause else {
            return FilterOutcome(decision: .pass, reason: .notPlayPause)
        }
        return FilterOutcome(decision: .block, reason: .absorbedAsNowPlayingDestination)
    }
}
