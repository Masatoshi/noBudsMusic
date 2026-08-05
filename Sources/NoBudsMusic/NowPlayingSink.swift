import Foundation
import MediaPlayer
import NoBudsMusicCore
import os

/// Claims the Now Playing destination and discards the Play/Pause commands that
/// would otherwise launch Music.app.
///
/// `TECH_RESEARCH.md` M11 established that a headset tap reaches `mediaremoted`
/// as a MediaRemote command and is routed to whatever holds the Now Playing
/// destination — and that when nothing holds it, macOS launches something.
/// Holding it and doing nothing removes the reason to launch.
///
/// **This is a measurement instrument first.** It logs every command it
/// receives, because the open questions in ADR 0003 — does the keyboard route
/// here too, does a real player take the destination back — are answered by
/// what shows up in this log, not by reading the API documentation.
///
/// It knows nothing about which device produced a command. Nothing on this path
/// does; see `EventFilter`.
@MainActor
final class NowPlayingSink {
    private let filter = EventFilter()
    private let diagnostics: DiagnosticsLog
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "nowPlaying")

    private var isActive = false
    private var handlers: [(MPRemoteCommand, Any)] = []

    /// Called after every absorbed or observed command so the UI can refresh.
    var onEvent: (@MainActor (DiagnosticsEntry) -> Void)?

    init(diagnostics: DiagnosticsLog) {
        self.diagnostics = diagnostics
    }

    var isHoldingDestination: Bool { isActive }

    // MARK: - Lifecycle

    /// Claims the destination. Idempotent.
    func activate() {
        guard !isActive else { return }

        let center = MPRemoteCommandCenter.shared()

        // Only Play/Pause is in scope. The others are registered anyway, and
        // deliberately refused rather than absorbed, so the log shows whether
        // they route here — which is how ADR 0003's "does this swallow
        // everything" question gets answered.
        register(center.playCommand, key: .play, absorb: true)
        register(center.pauseCommand, key: .play, absorb: true)
        register(center.togglePlayPauseCommand, key: .play, absorb: true)
        register(center.nextTrackCommand, key: .next, absorb: false)
        register(center.previousTrackCommand, key: .previous, absorb: false)

        // Claiming the destination needs a Now Playing item; an app with no
        // metadata is not a player as far as MediaRemote is concerned. Whether
        // this is enough without actually producing audio is measurement
        // question 1 in ADR 0003.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "noBudsMusic",
            MPMediaItemPropertyArtist: "Play/Pause is being discarded",
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
            MPMediaItemPropertyPlaybackDuration: 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing

        isActive = true
        logger.notice("claimed the Now Playing destination")
    }

    /// Releases the destination so real players are unaffected. Idempotent.
    func deactivate() {
        guard isActive else { return }

        for (command, token) in handlers {
            command.removeTarget(token)
        }
        handlers.removeAll()

        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        isActive = false
        logger.notice("released the Now Playing destination")
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            activate()
        } else {
            deactivate()
        }
    }

    // MARK: - Commands

    private func register(_ command: MPRemoteCommand, key: MediaKey, absorb: Bool) {
        command.isEnabled = true
        let token = command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.handle(key: key, absorb: absorb)
        }
        handlers.append((command, token))
    }

    private func handle(key: MediaKey, absorb: Bool) -> MPRemoteCommandHandlerStatus {
        // `isEnabled: absorb` rather than a settings read: the sink is only
        // registered while Status is ON, and `absorb` encodes whether this
        // particular command is in scope at all.
        let outcome = filter.decide(key: key, isEnabled: absorb)
        let entry = DiagnosticsEntry(key: key, outcome: outcome)
        diagnostics.append(entry)
        onEvent?(entry)

        // `.success` means handled — the command stops here and nothing is
        // launched. `.noSuchContent` lets the system look elsewhere, which for
        // an out-of-scope command is what should happen.
        return outcome.isBlocked ? .success : .noSuchContent
    }
}
