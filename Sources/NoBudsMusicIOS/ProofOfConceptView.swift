import MediaPlayer
import SwiftUI

/// Deliberately plain. The interesting output is the log, not the screen:
///
/// ```
/// idevicesyslog -u <udid> | grep -iE 'noBudsMusic|mediaremoted'
/// ```
///
/// What matters in the car is whether `Destination app com.apple.Music not
/// available ... command requested a launch` still appears after connecting.
struct ProofOfConceptView: View {
    @State private var sink = NowPlayingSink()
    @State private var tone = SilentTone()
    @State private var isHolding = false
    @State private var commandCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Destination") {
                    LabeledContent("Held", value: isHolding ? "yes" : "no")
                    LabeledContent("Commands seen", value: "\(commandCount)")
                }

                Section("Variant 1 — no audio") {
                    Button("Hold the destination") {
                        sink.activate()
                        isHolding = sink.isHoldingDestination
                    }
                    Button("Release") {
                        sink.deactivate()
                        isHolding = sink.isHoldingDestination
                    }
                }

                Section {
                    Button("Play 1s of silence, then hold") {
                        tone.play(seconds: 1.0)
                        sink.activate()
                        isHolding = sink.isHoldingDestination
                    }
                } header: {
                    Text("Variant 2 — one second of silence")
                } footer: {
                    Text(
                        """
                        Only if variant 1 fails. Connect to CarPlay with the \
                        destination held and see whether Music still launches.
                        """
                    )
                }
            }
            .navigationTitle("noBudsMusic PoC")
        }
        .task {
            // Variant 1 on launch. In a car the app should already hold the
            // destination by the time CarPlay connects, so making that the
            // default costs one less thing to remember before driving. The
            // buttons are for releasing it and for trying variant 2.
            sink.activate()

            // Poll rather than observe: the sink is deliberately passive and has
            // no change notification, and this screen is scaffolding.
            while !Task.isCancelled {
                isHolding = sink.isHoldingDestination
                commandCount = sink.forwardedCommandCount
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
