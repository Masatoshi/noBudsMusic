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
/// Every command is logged. There is no diagnostics UI; `just logs` is the
/// interface, and absorbed commands are logged at `.notice` so they survive
/// into `log show` and `just logs-dump`.
///
/// It knows nothing about which device produced a command. Nothing on this path
/// does; see `EventFilter`.
@MainActor
final class NowPlayingSink {
    private let filter = EventFilter()
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "nowPlaying")

    private var isActive = false
    private var handlers: [(MPRemoteCommand, Any)] = []

    var isHoldingDestination: Bool { isActive }

    // MARK: - Lifecycle

    /// Claims the destination. Idempotent.
    func activate() {
        guard !isActive else { return }

        let center = MPRemoteCommandCenter.shared()

        // Only Play/Pause is in scope. Next and Previous are registered anyway
        // and deliberately forwarded, so the headset's other gestures keep
        // working and the log shows that they arrive here at all.
        register(center.playCommand, key: .play, absorb: true)
        register(center.pauseCommand, key: .play, absorb: true)
        register(center.togglePlayPauseCommand, key: .play, absorb: true)
        register(center.nextTrackCommand, key: .next, absorb: false)
        register(center.previousTrackCommand, key: .previous, absorb: false)

        // Claiming the destination needs a Now Playing item; an app with no
        // metadata is not a player as far as MediaRemote is concerned. Measured
        // sufficient without producing any audio (M12).
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "noBudsMusic",
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
            MPMediaItemPropertyPlaybackDuration: 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
        ]

        // `.playing`, and that is deliberate despite M19.
        //
        // `.playing` outranks real players and steals their Play/Pause; but
        // `.paused` is never chosen as the destination at all, so it does not
        // prevent the launch either (M21). Neither is safe on its own.
        //
        // What makes `.playing` safe here is *when* it is declared: the sink is
        // only activated while nothing is playing audio, and is deactivated the
        // moment something starts. `AudioActivityMonitor` drives that, so there
        // is never a real player to steal from.
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
        // registered while enabled, and `absorb` encodes whether this particular
        // command is in scope at all.
        let outcome = filter.decide(key: key, isEnabled: absorb)

        if outcome.isBlocked {
            logger.notice(
                """
                \(key.rawValue, privacy: .public) discarded \
                (\(outcome.reason.rawValue, privacy: .public))
                """
            )
        } else {
            logger.debug(
                """
                \(key.rawValue, privacy: .public) forwarded \
                (\(outcome.reason.rawValue, privacy: .public))
                """
            )
        }

        // `.success` means handled — the command stops here and nothing is
        // launched. `.noSuchContent` lets the system look elsewhere, which for
        // an out-of-scope command is what should happen.
        return outcome.isBlocked ? .success : .noSuchContent
    }
}
