# Apple Music launching itself on iOS

Measured 2026-08-05 on iPhone 16 Pro (iPhone17,1), iOS 27.0, with a Bluetooth
headset. `TECH_RESEARCH.md` covers macOS; this file covers iOS, and exists
mainly to record where the two differ.

The investigation started from CarPlay, on the assumption that a car was needed
to reproduce it. That turned out to be wrong, which is the most useful thing in
this document.

## The mechanism is the same as macOS

Tapping a Bluetooth headset while nothing is playing produces this:

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play, SenderBundleIdentifier = <com.apple.BTAvrcp>>,
              and command requested a launch. Enqueueing command for later
              execution.
mediaremoted: Request: MRDLaunchApplicationWithReason<command<Play>> for
              com.apple.Music
```

That is the macOS line, on iOS, word for word. It is preceded by the same
precondition:

```text
mediaremoted: No context for context-sensitive command <command = Play>
```

No Now Playing destination, so the system launches one. Registering as that
destination would remove the reason to launch, exactly as on macOS.

**CarPlay is not required to reproduce this.** A headset tap on a locked phone
is enough. Everything below was measured at a desk with no car involved.

## What "it plays but the app is not open" means

Music.app *is* launched — as a background process with no UI:

```text
SpringBoard(RunningBoardServices): Sending launch request:
              <RBSLaunchRequest| app<com.apple.Music>; "FBApplicationProcess">
runningboardd: Creating and launching job for: app<com.apple.Music>:5435
mediaremoted:  Sending previously queued command <command = Play>
```

`mediaremoted` queues the command, launches Music, then replays the command
against it. Audio starts, and nothing appears on screen. Unlocking the phone
afterwards shows no Music window, which reads as "it played without launching" —
but the process is there.

## The destination is sticky

A second tap two minutes later did not launch anything:

```text
path = 【 LOCL (iPhone) ❯ com.apple.Music (5435) ミュージック ❯ Music 】
```

Music was still the destination and the command routed straight to it. Once
something occupies the slot, later taps cost nothing. That is what makes an
occupy-the-slot fix plausible here, and it is worth knowing that the occupation
does not have to be re-established per tap.

## Differences from macOS

### The sender is `com.apple.BTAvrcp`, not `bluetoothd`

| | Sender |
| --- | --- |
| macOS | `com.apple.bluetoothd` |
| iOS | `com.apple.BTAvrcp` (via `com.apple.AVRCP`) |

Same role, different process. Anything matching on the macOS bundle identifier
will not match here.

### The command carries a device identity

This one inverts a macOS conclusion:

```text
kMRMediaRemoteOptionSourceID = "74:74:46:03:D7:4D"
```

That is the headset's Bluetooth address, on the command. ADR 0003 concluded that
per-device rules are impossible because a MediaRemote command carries no device
identity — that holds on macOS, and does **not** hold on iOS. Whether the value
is reachable from public API is a separate and unanswered question, but the
information is present at this layer.

### There is a private switch for exactly this behaviour

```text
[MediaServerNowPlayingDataSource]
AVSystemController.AVSystemController_ShouldIgnorePlayCommandsFromAccessoryAttribute=0
```

`mediaremoted` reads it on every accessory command.
`AVSystemController_AllowAppToInitiatePlaybackTemporarilyAttribute` appears
alongside it.

Both live in `AVSystemController`, which is **private** (Celestial.framework),
undocumented, and unusable in anything shipping through the App Store. No
user-facing setting was found that maps to it. Recorded because it shows the
concept exists inside the system, not because it is a route.

## The open question

On macOS the app holds the destination silently and indefinitely, producing no
audio at all (M12). iOS does not obviously allow that: an app that is not
playing gets suspended, and background audio is intended for audio playback.
App Store Review Guideline 2.5.4:

> Multitasking apps may only use background services for their intended
> purposes: VoIP, audio playback, location, task completion, local
> notifications, etc.

There is no explicit prohibition on silence in that text, so this is a review
risk rather than a settled rule.

**The proposal to test is to play about a second of silence and stop**, rather
than hold the slot with no audio. The sticky-destination measurement above says
the app would not need to keep playing to keep the slot. What is not yet
measured is whether an app that has stopped remains the destination on iOS, and
for how long — on macOS `.paused` is never chosen as the destination at all
(M20, M21), so the two systems cannot be assumed to agree.

## What still needs measuring

Reproduction no longer needs a car, so most of the original matrix is gone.
What is left:

| # | Question | Why it matters |
| --- | --- | --- |
| 1 | Does connecting to CarPlay go through the same command path? | The goal is CarPlay; the headset is only a convenient stand-in |
| 2 | Can a third-party app take the destination on iOS at all? | If not, nothing else matters |
| 3 | Does it keep the destination after it stops playing, and for how long? | Decides whether one second of silence is enough |
| 4 | Does it survive backgrounding, locking, and jetsam? | Decides whether the fix is durable |
| 5 | Does `.noSuchContent` forward on iOS as it does on macOS? | Decides whether real players keep control |
| 6 | Is the tap still handled after a reboot with no user interaction? | Decides whether it needs launching by hand |

Question 1 is first because it can invalidate the rest. A headset tap is an
explicit Play command from the accessory. A CarPlay connection might instead
restore a previous session or trigger autoplay on route change, and that would
be a different trigger reaching Music by a different route — in which case
occupying the Now Playing destination would not fix the case this is for.

The headset result says the *mechanism exists* on iOS. It does not say CarPlay
uses it.

## How to answer question 1

Not by capturing a log in the car. The fix does not depend on which process sent
the command — if the destination is occupied, no sender produces a launch
request. So the cheaper move is to build the PoC and connect to CarPlay with it
running:

- Music does not launch: same path, and the fix already works.
- Music still launches: there is a second path. *Then* pull a log archive
  (`idevicesyslog archive <path> --age-limit <seconds>`) and find it.

Either way it is one trip to the car, and the first outcome finishes the job
instead of merely informing it.

## Two variants worth trying in that order

The PoC is `NowPlayingSink.swift` from the macOS app, near enough unchanged. The
open part is how the app takes the destination:

| Variant | What it establishes |
| --- | --- |
| Take the destination with no audio at all | Whether iOS behaves like macOS (M12). If it does, iOS needs nothing extra |
| Play about a second of silence, then stop | Whether the destination survives stopping, and for how long |

The first is worth trying before the second. If it works, the iOS app is the
same shape as the macOS one and the background-audio review question in 2.5.4
never arises.

**Operationally, the app has to already hold the destination when the car
connects.** If the silence variant turns out to be necessary, that implies a
step before driving — launching the app, or something equivalent — and that is a
usability problem, not just an implementation detail. It is a reason to prefer
the first variant beyond simplicity.

## Unaffected by this document

Whether Apple Music is installed, subscribed, or signed in was not varied.
Neither was the iOS version — everything here is iOS 27.0. Earlier versions may
route differently, and this document should not be read as covering them.

## References

- [CarPlay entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
- [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)
- [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
