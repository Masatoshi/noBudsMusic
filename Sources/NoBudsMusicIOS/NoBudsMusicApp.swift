import SwiftUI

/// Proof of concept, not a product.
///
/// It exists to answer one question from `docs/ios-carplay-music-autolaunch.md`:
/// can a third-party app hold the Now Playing destination on iOS, and does that
/// stop `mediaremoted` requesting a launch of Music? The macOS app does this
/// with no audio at all (M12); whether iOS allows the same is the whole
/// experiment.
///
/// There are two variants to try, in this order:
///
/// 1. Hold the destination with no audio. If this works, the iOS app is the
///    same shape as the macOS one and nothing else is needed.
/// 2. Play a second of silence first. Only if 1 fails — it brings an audio
///    session and an App Store review conversation with it.
@main
struct NoBudsMusicApp: App {
    var body: some Scene {
        WindowGroup {
            ProofOfConceptView()
        }
    }
}
