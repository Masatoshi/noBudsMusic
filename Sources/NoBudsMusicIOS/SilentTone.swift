import AVFoundation
import os

/// Variant 2: take the Now Playing destination by briefly playing silence.
///
/// Only needed if holding the destination with no audio turns out not to work
/// on iOS. The iOS measurement in `docs/ios-carplay-music-autolaunch.md` showed
/// the destination is sticky — Music kept it two minutes after a tap, with no
/// further playback — so a short burst should be enough to claim it if a claim
/// requires audio at all.
///
/// How long it survives afterwards is exactly what this is here to find out.
@MainActor
final class SilentTone {
    private let logger = Logger(subsystem: "jp.kaizudenki.noBudsMusic", category: "silentTone")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isWired = false

    /// Plays `seconds` of silence, then does whatever `then` says. Errors are
    /// logged, not thrown: every failure here is a result worth recording
    /// rather than an exception to handle.
    ///
    /// The three endings are three different experiments:
    ///
    /// - `.stop` tears the engine down. Measured: the app is popped off the Now
    ///   Playing stack on the next Play command.
    /// - `.pause` keeps the engine running and the session active, which is the
    ///   state Audible was in while it held the slot. Untested here.
    /// - `.loop` never stops, which certainly holds the slot and certainly
    ///   consumes the tap.
    enum Ending {
        case stop
        case pause
        case loop
    }

    func play(seconds: Double = 1.0, then ending: Ending = .stop) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            if !isWired {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: nil)
                isWired = true
            }

            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            let frames = AVAudioFrameCount(format.sampleRate * seconds)
            guard
                frames > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
            else {
                logger.error("could not allocate a silent buffer")
                return
            }
            // Left as allocated: an AVAudioPCMBuffer starts zeroed, and zero
            // samples are silence.
            buffer.frameLength = frames

            try engine.start()

            switch ending {
            case .loop:
                player.scheduleBuffer(buffer, at: nil, options: [.loops])
            case .stop, .pause:
                player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                    Task { @MainActor in
                        if ending == .stop { self?.stop() } else { self?.pause() }
                    }
                }
            }

            player.play()
            logger.notice(
                "playing \(seconds, privacy: .public)s of silence, then \(String(describing: ending), privacy: .public)"
            )
        } catch {
            logger.error("silent tone failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stops playback and tears the engine down. The audio session is left
    /// active deliberately — deactivating it is a second variable, and this
    /// ending already loses the slot without it.
    func stop() {
        player.stop()
        engine.stop()
        logger.notice("silence stopped")
    }

    /// Pauses without tearing anything down: the engine keeps running and the
    /// session stays active. This is the state a real player is in when it is
    /// paused and still holding the Now Playing slot, which `stop()` is not.
    func pause() {
        player.pause()
        logger.notice("silence paused, engine still running")
    }

    /// Releases everything, for when the app should stop occupying the slot.
    func release() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        logger.notice("audio session released")
    }
}
