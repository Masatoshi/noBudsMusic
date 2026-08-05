import Foundation

/// A remote control command, for the log.
///
/// Nothing branches on this any more. The app forwards every command it
/// receives — it occupies the Now Playing destination rather than filtering it
/// (ADR 0003) — so this exists only so the log says which command arrived.
public enum MediaKey: String, Sendable, CaseIterable {
    /// Play, Pause and Play/Pause collapse to one case. A headset tap is a
    /// single gesture, and which transport state it resolves to is the real
    /// player's business, not this app's.
    case play
    case next
    case previous
}
