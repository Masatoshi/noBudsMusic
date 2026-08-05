import Foundation
import MediaPlayer
import NoBudsMusicCore
import os

/// Occupies the Now Playing destination so `mediaremoted` never has to launch a
/// player, and forwards every command it receives.
///
/// This app blocks nothing. `TECH_RESEARCH.md` M11 showed a headset tap reaches
/// `mediaremoted` as a MediaRemote command from `bluetoothd`, and M15 showed
/// Music.app is launched precisely when no player holds the destination. The
/// fix is to hold it — and then to get out of the way.
///
/// Every handler answers `.noSuchContent`, never `.success`:
///
/// - When a real player exists, `mediaremoted` passes the command on to it, so
///   the headset still controls Chrome, Amazon Music and the rest (M24).
/// - When none exists, the command goes nowhere and **no launch is requested**,
///   which is the entire bug.
///
/// Answering `.success` also prevents the launch, but consumes the command, and
/// that made real players uncontrollable (M19). The whole design turns on this
/// return value.
///
/// There is no diagnostics UI; `just logs` is the interface.
@MainActor
final class NowPlayingSink {
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "nowPlaying")

    private var isActive = false
    private var handlers: [(MPRemoteCommand, Any)] = []

    var isHoldingDestination: Bool { isActive }

    // MARK: - Lifecycle

    /// Claims the destination. Idempotent.
    func activate() {
        guard !isActive else { return }

        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand, key: .play)
        register(center.pauseCommand, key: .play)
        register(center.togglePlayPauseCommand, key: .play)
        register(center.nextTrackCommand, key: .next)
        register(center.previousTrackCommand, key: .previous)

        // Claiming the destination needs a Now Playing item; an app with no
        // metadata is not a player as far as MediaRemote is concerned. Measured
        // sufficient without producing any audio (M12).
        //
        // `.playing` rather than `.paused`: a paused app is never chosen as the
        // destination at all, so it does not prevent the launch (M21). Claiming
        // `.playing` used to steal control from real players, but that was a
        // consequence of answering `.success`, not of the state itself — with
        // `.noSuchContent` they take the destination back as soon as they play.
        // Control Center shows this app whenever nothing else is playing, and
        // that cannot be avoided: occupying the Now Playing slot means
        // appearing in Now Playing. Measured — omitting the title only falls
        // back to the app name, so the choice is what the line says, not
        // whether it appears.
        //
        // Given that, it says what the app is doing rather than just its name.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: NSLocalizedString(
                "nowPlaying.title",
                comment: "Shown in Control Center while holding the slot"
            ),
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
            MPMediaItemPropertyPlaybackDuration: 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing

        isActive = true
        logger.notice("holding the Now Playing destination")
    }

    /// Releases the destination. Idempotent.
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

    private func register(_ command: MPRemoteCommand, key: MediaKey) {
        command.isEnabled = true
        let token = command.addTarget { [weak self] _ in
            self?.logger.notice("\(key.rawValue, privacy: .public) forwarded")
            // Never `.success`. See the note on this type.
            return .noSuchContent
        }
        handlers.append((command, token))
    }
}
