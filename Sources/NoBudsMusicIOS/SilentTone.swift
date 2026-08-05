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

    /// Plays `seconds` of silence and stops. Errors are logged, not thrown:
    /// every failure here is a result worth recording rather than an exception
    /// to handle.
    func play(seconds: Double = 1.0) {
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
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor in self?.stop() }
            }
            player.play()
            logger.notice("playing \(seconds, privacy: .public)s of silence")
        } catch {
            logger.error("silent tone failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stops playback but leaves the audio session active, because deactivating
    /// it is one of the things that might cost the destination. Whether it does
    /// is part of the experiment.
    func stop() {
        player.stop()
        engine.stop()
        logger.notice("silence stopped")
    }
}
