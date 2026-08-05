import Testing

@testable import NoBudsMusicCore

@Suite("EventFilter")
struct EventFilterTests {
    let filter = EventFilter()

    @Test("Play/Pause is absorbed when Status is ON")
    func absorbsPlayPause() {
        let outcome = filter.decide(key: .play, isEnabled: true)
        #expect(
            outcome == FilterOutcome(decision: .block, reason: .absorbedAsNowPlayingDestination)
        )
    }

    // Status OFF has to mean "not holding the destination", not "holding it and
    // ignoring commands" — the latter would still displace a real player.
    @Test("Status OFF passes")
    func statusOffPasses() {
        let outcome = filter.decide(key: .play, isEnabled: false)
        #expect(outcome == FilterOutcome(decision: .pass, reason: .statusOff))
    }

    // The headset's other gestures must keep working. Next and Previous are
    // forwarded so whatever is actually playing still receives them.
    @Test(
        "Nothing but Play/Pause is absorbed",
        arguments: MediaKey.allCases.filter { $0 != .play }
    )
    func otherCommandsForwarded(key: MediaKey) {
        let outcome = filter.decide(key: key, isEnabled: true)
        #expect(outcome == FilterOutcome(decision: .pass, reason: .notPlayPause))
    }

    @Test("Only Play counts as Play/Pause")
    func playPauseClassification() {
        #expect(MediaKey.play.isPlayPause)
        for key in MediaKey.allCases where key != .play {
            #expect(!key.isPlayPause)
        }
    }
}
