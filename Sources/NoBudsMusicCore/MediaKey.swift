import Foundation

/// A remote control command this app is asked to handle.
///
/// Deliberately tiny. It used to carry `NX_KEYTYPE_*` raw values and a HID
/// Consumer usage mapping, because the app expected to classify events off the
/// HID and event-tap paths. `TECH_RESEARCH.md` M11 eliminated both: commands
/// arrive through `MPRemoteCommandCenter`, already identified, so there is
/// nothing left to classify.
public enum MediaKey: String, Sendable, CaseIterable {
    /// Play, Pause and Play/Pause collapse to one case. A headset tap is a
    /// single gesture, and which transport state it resolves to is not this
    /// app's business — only whether it should reach a player.
    case play
    case next
    case previous

    /// The only command this app may absorb.
    public var isPlayPause: Bool {
        self == .play
    }
}
