import Foundation

/// A media key observed on the system-defined event stream.
///
/// Raw values match the `NX_KEYTYPE_*` constants from `IOKit/hidsystem/ev_keymap.h`.
/// Only the subset this app needs to classify is modelled; anything else stays
/// unrecognised and is passed through untouched.
///
/// The volume keys are modelled even though they are never in scope, so that
/// "volume is unaffected" is an assertion in the test suite rather than an
/// assumption.
public enum MediaKey: Int32, Sendable, CaseIterable {
    case volumeUp = 0  // NX_KEYTYPE_SOUND_UP
    case volumeDown = 1  // NX_KEYTYPE_SOUND_DOWN
    case mute = 7  // NX_KEYTYPE_MUTE
    case play = 16  // NX_KEYTYPE_PLAY (play/pause toggle)
    case next = 17  // NX_KEYTYPE_NEXT
    case previous = 18  // NX_KEYTYPE_PREVIOUS
    case fastForward = 19  // NX_KEYTYPE_FAST
    case rewind = 20  // NX_KEYTYPE_REWIND

    /// The only key this app may ever block.
    ///
    /// macOS reports a headset tap as a single `NX_KEYTYPE_PLAY` regardless of
    /// whether it resolves to Play or Pause, so this is deliberately narrow.
    public var isPlayPause: Bool {
        self == .play
    }

    /// Classifies a raw system-defined key code, returning `nil` for anything
    /// outside the modelled set.
    public static func from(rawKeyCode: Int32) -> MediaKey? {
        MediaKey(rawValue: rawKeyCode)
    }

    /// Classifies a HID Consumer Page (0x0C) usage.
    ///
    /// A second namespace onto the same enum: the `CGEventTap` path reports
    /// `NX_KEYTYPE_*` codes, while the IOHID path reports HID usages, and the
    /// two do not share numbering. Both have to land on the same `MediaKey` so
    /// `EventFilter` sees one vocabulary regardless of which path observed the
    /// event.
    ///
    /// Returns `nil` for any usage outside the modelled set — including the
    /// large majority of Consumer Page usages, which are display, browser and
    /// application-launch controls this app has no interest in.
    public static func from(consumerUsage: Int) -> MediaKey? {
        switch consumerUsage {
        // A headset tap is reported as a single Play/Pause toggle; discrete
        // Play and Pause exist too and are treated as the same key, because the
        // spec's scope is the Play/Pause gesture rather than the resulting
        // transport state.
        case 0xCD, 0xB0, 0xB1: .play
        case 0xB5: .next
        case 0xB6: .previous
        case 0xB3: .fastForward
        case 0xB4: .rewind
        case 0xE9: .volumeUp
        case 0xEA: .volumeDown
        case 0xE2: .mute
        default: nil
        }
    }
}
