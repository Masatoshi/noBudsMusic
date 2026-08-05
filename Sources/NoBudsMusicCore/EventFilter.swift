import Foundation

/// What to do with an observed media key event.
public enum FilterDecision: String, Sendable, Equatable, Codable {
    case pass
    case block
}

/// Why `EventFilter` decided the way it did.
///
/// Surfaced verbatim in the Diagnostics screen: the brief requires that a
/// non-blocked event can be explained, not just observed.
public enum FilterReason: String, Sendable, Equatable, Codable {
    /// Global Status is OFF.
    case statusOff
    /// Not a Play/Pause key. Volume, Next, Previous and friends are never
    /// in scope.
    case notPlayPause
    /// The source device could not be determined. Passing through on purpose.
    case sourceUnidentified
    /// Identified, but not a Bluetooth device. Never blockable.
    case sourceNotBluetooth
    /// A Bluetooth device with no saved rule.
    case deviceNotConfigured
    /// A Bluetooth device whose rule is off.
    case deviceNotBlocked
    /// Global Status ON, Bluetooth device, rule on.
    case deviceBlocked
    /// Absorbed as the Now Playing destination. No source was available to
    /// check, by construction — see `decideForNowPlaying`.
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

/// The single place that decides whether an event is blocked.
///
/// Two gates, in order: the global Status, then the per-device rule. Both must
/// say yes.
///
/// 1. Status OFF               -> pass.
/// 2. Not Play/Pause           -> pass.
/// 3. Source unidentified      -> pass. Never block on a guess.
/// 4. Source not Bluetooth     -> pass. Keyboards and USB are out of reach.
/// 5. No rule, or rule off     -> pass.
/// 6. Bluetooth + rule on      -> block.
///
/// Rule 3 is the safety property of this app. A false positive silently breaks
/// the user's keyboard media keys, which is worse than the bug being fixed.
public struct EventFilter: Sendable {
    public init() {}

    public func decide(
        key: MediaKey,
        source: EventSource,
        rule: DeviceRule?,
        isEnabled: Bool
    ) -> FilterOutcome {
        guard isEnabled else {
            return FilterOutcome(decision: .pass, reason: .statusOff)
        }
        guard key.isPlayPause else {
            return FilterOutcome(decision: .pass, reason: .notPlayPause)
        }
        guard case .device(let identifier, let info) = source else {
            return FilterOutcome(decision: .pass, reason: .sourceUnidentified)
        }
        guard info.transport.isBluetooth else {
            return FilterOutcome(decision: .pass, reason: .sourceNotBluetooth)
        }
        guard let rule, rule.identifier == identifier else {
            return FilterOutcome(decision: .pass, reason: .deviceNotConfigured)
        }
        // `isEffective` re-checks the transport against the stored rule, so a
        // rule saved while the device reported Bluetooth cannot act on a device
        // that now reports something else.
        guard rule.isEffective else {
            return FilterOutcome(decision: .pass, reason: .deviceNotBlocked)
        }
        return FilterOutcome(decision: .block, reason: .deviceBlocked)
    }

    /// The rule for the Now Playing path, which has **no source to identify**.
    ///
    /// A MediaRemote command carries no device identity: every headset arrives
    /// as `com.apple.bluetoothd`. There is nothing to attribute, so this cannot
    /// go through `decide(key:source:rule:isEnabled:)` — that method would
    /// correctly refuse to block an unidentified source, and weakening it to
    /// accommodate this path would destroy the safety property that protects
    /// keyboards on every other path.
    ///
    /// So the trade-off lives here, in a signature that does not take a source
    /// because none exists:
    ///
    /// 1. Status OFF     -> forward. The app should not hold the destination.
    /// 2. Not Play/Pause -> forward. Volume, Next, Previous stay out of scope.
    /// 3. Otherwise      -> absorb.
    ///
    /// The consequence is deliberate and documented in ADR 0003: on this path
    /// the app cannot tell a headset tap from a keyboard media key. Limiting
    /// *when* it holds the destination is the only available mitigation, and it
    /// is not this method's job.
    public func decideForNowPlaying(key: MediaKey, isEnabled: Bool) -> FilterOutcome {
        guard isEnabled else {
            return FilterOutcome(decision: .pass, reason: .statusOff)
        }
        guard key.isPlayPause else {
            return FilterOutcome(decision: .pass, reason: .notPlayPause)
        }
        return FilterOutcome(
            decision: .block,
            reason: .absorbedAsNowPlayingDestination
        )
    }
}
