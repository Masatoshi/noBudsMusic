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
    @State private var answerWithSuccess = false

    var body: some View {
        NavigationStack {
            List {
                Section("Destination") {
                    LabeledContent("Held", value: isHolding ? "yes" : "no")
                    LabeledContent("Commands seen", value: "\(commandCount)")
                }

                Section {
                    Picker("Answer with", selection: $answerWithSuccess) {
                        Text(".noSuchContent").tag(false)
                        Text(".success").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: answerWithSuccess) { _, useSuccess in
                        sink.commandResponse = useSuccess ? .success : .noSuchContent
                    }
                } footer: {
                    Text(
                        """
                        `.noSuchContent` is the macOS design, and on iOS it makes \
                        the app pop-eligible — the system removes it from the Now \
                        Playing stack five seconds later. `.success` should keep \
                        the slot, and may consume the command instead, which is \
                        what M19 measured on macOS.
                        """
                    )
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
                    Button("1s, then stop") {
                        tone.play(seconds: 1.0, then: .stop)
                        sink.activate()
                        isHolding = sink.isHoldingDestination
                    }
                    Button("1s, then pause (keep the session)") {
                        tone.play(seconds: 1.0, then: .pause)
                        sink.activate()
                        isHolding = sink.isHoldingDestination
                    }
                    Button("Loop silence") {
                        tone.play(seconds: 1.0, then: .loop)
                        sink.activate()
                        isHolding = sink.isHoldingDestination
                    }
                    Button("Release the session", role: .destructive) {
                        tone.release()
                        sink.deactivate()
                        isHolding = sink.isHoldingDestination
                    }
                } header: {
                    Text("Variant 2 — one second of silence")
                } footer: {
                    Text(
                        """
                        Stopping loses the slot on the next Play — measured. \
                        Pausing is the state a real player holds it in, and is \
                        untested. Looping certainly holds it and certainly \
                        consumes the tap.
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
