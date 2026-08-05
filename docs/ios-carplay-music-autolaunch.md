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

## CarPlay does not use that path

Measured 2026-08-05, 16:57–17:02, connecting to a car. Music.app was launched
and appeared on the CarPlay screen as playing — showing a U2 album — while no
audio played, and opening Music on the phone showed it stopped.

`mediaremoted` did not launch it:

| | Headset tap (16:34) | CarPlay connect (17:00) |
| --- | --- | --- |
| MediaRemote commands received | 1 | 2 |
| `MRDLaunchApplicationWithReason` | 1 | **0** |

The launch came from CarPlay itself:

```text
runningboardd: Acquiring assertion targeting app<com.apple.Music>
               from originator [osservice<com.apple.CarPlayApp>:5663]
               with description <RBSAssertionDescriptor|
               "FBApplicationProcess" ...>
```

So the mechanism this document opens with — no destination, therefore a launch
request — **is not what happens when a car connects.** CarPlay launches Music
directly, without asking `mediaremoted` whether a destination exists.

### What that does and does not rule out

It rules out the explanation. It does not rule out the fix, and there is
behavioural evidence that the fix is the right shape.

**CarPlay does not launch Music when something else is already playing.** With a
YouTube tab going, connecting produces no Music. This is well enough known that
the common workaround is to make Spotify the app you last played from. So
`com.apple.CarPlayApp` is not launching Music unconditionally — it is filling
its Now Playing screen, and Music is the default when there is no candidate.

That matches the capture: Music was launched, displayed as playing, and produced
no audio. It was put there to be shown, not to play.

So the fix is still "occupy the slot", but for a different reason than this
document originally gave. Not *so that no launch is requested* — none is. It is
so that CarPlay finds a candidate and does not fall back to its default.

The open part is what counts as a candidate. The evidence above is from apps
that are genuinely playing audio. This app declares `.playing` and produces
none. Whether that is enough is exactly what variant 1 tests, and the case for
variant 2 — a real second of silence — is that it makes the app
indistinguishable from the YouTube tab that is already known to work.

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

## Measured with the proof of concept

Run on the device 2026-08-05, iOS 27.0. Three results, and the third inverts the
macOS design.

### Declaring the state is not enough

Setting `nowPlayingInfo` and `playbackState = .playing` with no audio — what the
macOS app does, and what M12 measured sufficient there — does **not** make the
app the destination on iOS. `mediaremoted` accepts the registration and logs the
entitlement check, then routes elsewhere:

```text
mediaremoted: Retrieved application-identifier from SecTask:
              applicationID=8KS5G58L37.jp.kaizudenki.noBudsMusic.poc
mediaremoted: MRDLaunchApplicationWithReason<command<Play>> for com.audible.iphone
```

A tap launched Audible, the last app that had played. The proof of concept never
received the command.

That also refines the earlier finding. `mediaremoted` does not launch Music
unconditionally when there is no destination — it launches **the last app that
played**, and falls back to Music when there is none. Music appeared at 16:34
because nothing else was recent.

### A second of silence is enough to take it

With the audio session active and one second of silence played, the app becomes
the destination and the command reaches it:

```text
mediaremoted: setting nowPlayingApplicationPID to <6235>
mediaremoted: Posting ...nowPlayingApplicationIsPlayingDidChange with <Playing>
noBudsMusic PoC: [nowPlaying] play forwarded
```

No launch request was issued for that tap. So iOS reads the real playback state,
not the declared one, and silence counts as playback. Neither duration nor
volume is the variable — zero samples for one second was accepted.

### An app that answers Play without playing is popped

The app holds the destination only while it is playing. 1.4 seconds after the
silence ended:

```text
mediaremoted: Posting ...nowPlayingApplicationIsPlayingDidChange with <Not Playing>
```

And then, on the next tap, iOS removes it from a **stack** of Now Playing
applications, revealing whatever was underneath — which is why Audible surfaced
and played:

```text
18:21:24.519  Sending nowPlayingAppStackPopEligible command...
18:21:24.525  play answered   rawValue: 0        (.success)
18:21:29.522  [MediaServerNowPlayingDataSource] Popping nowPlayingAppStack..
```

**The return value is not what causes this.** That was the first reading here
and it was wrong: the pop-eligible marking is sent at 24.519, *before* the app
answers at 24.525, and the app was popped anyway while answering `.success` four
times. It is a property of dispatching the Play command, not of the reply.

What decides it is whether playback actually starts. A Play command is
dispatched as pop-eligible; if the app that receives it has not begun playing
about five seconds later, it comes off the stack. Which is a coherent rule — an
app that will not play when told to play has no business holding the slot.

So **a silent sink cannot work on iOS**, and no choice of return value rescues
it. `.noSuchContent` and `.success` are popped alike.

### Pausing holds the slot; stopping does not

Tearing the engine down was the wrong comparison. A real player that is paused
keeps its session and keeps the slot, and so does this app once it does the
same — `player.pause()` with the engine left running:

```text
18:27:03.386  silence paused, engine still running
              -- 38 seconds idle, no pop --
18:27:41.352  play answered            <- the tap still reached this app
18:27:46.338  Popping nowPlayingAppStack..
```

So there are two separate rules, and only the second is a problem:

| | Slot while idle | After a Play it does not act on |
| --- | --- | --- |
| `stop` — engine torn down | lost | — |
| `pause` — engine and session kept | **held, no decay in 38s** | popped after 5s |

Idle retention was not measured beyond 38 seconds, and no decay was seen in
that window.

The return value makes no difference under either ending. `.success` and
`.noSuchContent` were both tried with pausing and behaved identically, which is
independent confirmation that the pop is caused by not playing rather than by
the reply.

### Measured in the car: it works

Same car, 2026-08-05. The app was left holding the slot paused, and CarPlay
connected at 18:35:15 and disconnected at 18:35:50. **Music was not launched and
nothing played.**

| | 17:00, no app | 18:35, slot held |
| --- | --- | --- |
| `runningboardd` assertion on `com.apple.Music` from `CarPlayApp` | yes | **no** |
| `mediaremoted` mentions of `com.apple.Music` in the window | many | **0** |
| Audio | started | **none** |

The slot was this app's at connect time. `nowPlayingApplicationDisplayID` was
last set at 18:33:49 and stayed put — third-party bundles are redacted in that
field, so `<private>` is this app where `com.apple.Music` had been shown before:

```text
18:33:36  nowPlayingApplicationDisplayID to <com.apple.Music>
18:33:49  nowPlayingApplicationDisplayID to <private>
18:35:15  CarPlay connects
```

What CarPlay acquired assertions on during the connection was only its own
furniture — `CarRadio`, `CarPlayWallpaper`, `CarPlayTemplateUIHost`. At 17:00
the same query returned `app<com.apple.Music>`.

### Confirmed in the car, and the slot lasts

A second connection, 18:58:01, with the app holding the slot from a single
button press **11 minutes and 40 seconds earlier**:

```text
18:46:21  silence paused
18:46:18  nowPlayingApplicationDisplayID to <private>   (unchanged from here)
18:58:01  CarPlay connects — no Music launch, no audio
```

The CarPlay dashboard showed this app: its icon, "Music.app の自動起動を防止中"
as the title, and transport controls.

**The lock screen is not a readout of the slot.** The Now Playing widget stops
showing the app after about ten minutes, which looks like expiry and is not —
the destination was still this app twelve minutes on, and CarPlay displayed it.
Anything measuring retention by watching the lock screen will get this wrong.

Pressing play on the CarPlay transport does surface Music, on the rule above:
the app answers without playing, is popped five seconds later, and Music is what
is underneath. No audio plays. Not pressing it is the whole of the workaround.

### The "Now Playing" tile was never Music

Worth recording because it cost time. The CarPlay app grid has a tile labelled
*再生中* — "Now Playing" — which is CarPlay's own built-in Now Playing app, not
Apple Music. Seeing it while Music was the destination made it look like Music
was being displayed as playing, and it is simply a standard tile that is always
there.

### Why this may be enough for CarPlay

**Connecting to a car is not a Play command.** The rule that costs the slot is
answering Play without playing, and a CarPlay connection never asks. An app
holding the slot paused should therefore still be holding it when the car
connects — giving `com.apple.CarPlayApp` the candidate that stops it falling
back to Music.

What it gives up is the headset tap: tap once and the slot is gone five seconds
later, and the next tap goes wherever it would have gone anyway. That is the
case this investigation used as a stand-in, not the one it was for.

### What would hold the slot, and what it costs

Playing real audio — a silent file, a generated buffer, anything that keeps the
session running — does hold the slot, because that satisfies the rule above.
The cost is the point of the whole design: an app that plays when tapped is
consuming the tap, so Audible and YouTube can no longer be controlled from the
headset. On macOS `.noSuchContent` bought exactly that (M24), and iOS does not
sell it.

That trade is not automatically wrong. For the CarPlay case the desired outcome
is that connecting starts nothing, and an app that occupies the slot playing
silence delivers precisely that. It is the headset case it gives up, not the one
this investigation started from. Both should not be expected from one app on
iOS.

## Two causes, reported as one symptom

Public reports of this describe it as a single problem: connect the phone to the
car and Apple Music starts, often for people who have never used it. One such
thread is [here](https://x.com/tjwaggoner/status/2084760072748429712), from
2026-08-05, where one person is on CarPlay and the other says they do not use
CarPlay at all — only the factory Bluetooth interface. Both report it starting
within the past week.

That is second-hand and dated, not measurement, and it is recorded as a report
rather than as evidence. What makes it worth recording is that the two people
are describing **different mechanisms**:

| Route | What launches Music | Fixable by holding the slot |
| --- | --- | --- |
| Plain Bluetooth / AVRCP | `mediaremoted`, because there is no destination | **Yes** — measured here |
| CarPlay | `com.apple.CarPlayApp`, directly | Yes, but for a different reason |

The Bluetooth case is the one this document opens with and the one fully
accounted for: a Play command arrives, there is no Now Playing destination, and
the system launches the last app that played or Music if there was none.

The CarPlay case never issues a launch request at all. Occupying the slot works
against both, but for the second it works by giving CarPlay a candidate rather
than by removing a launch request.

Anyone diagnosing this from the symptom alone will conflate them, and a fix
verified against one says nothing about the other. That was the mistake made
here, and it cost most of a day.

### Recognising it

A few things make this identifiable from the symptom, which is otherwise easy to
blame on the car.

**It is often U2.** The album Music reaches for is frequently *Songs of
Innocence*, pushed into every iTunes library in 2014. It is there whether or not
anyone wanted it, so when Music starts with nothing of the user's own to play,
that is what comes out. The car in this investigation displayed exactly that.
Music the listener never chose, by a band whose album they never added, is a
strong signature.

**The person often does not use Apple Music at all.** Reports come from people
who say the app is not even set up, which fits: the launch is a system decision
about a destination, not a user or a playlist.

**It is not confined to CarPlay.** The same complaint arrives from people using
only the factory Bluetooth interface, and from people whose complaint is that
CarPlay prefers Music over the app they actually use. Those are the two routes
above.

Reports run at least from 2026-07-29 through 2026-08-05, in English and
Japanese. Dated because this may be specific to a recent iOS; everything
measured here is iOS 27.0 and nothing here establishes when it started.

## Unaffected by this document

Whether Apple Music is installed, subscribed, or signed in was not varied.
Neither was the iOS version — everything here is iOS 27.0. Earlier versions may
route differently, and this document should not be read as covering them.

### One head unit, and not a plain one

The CarPlay measurement is a single car: a Toyota, where CarPlay is started from
the head unit's own interface rather than being the primary screen. It connected
wirelessly, over the AirPlay transport:

```text
airplayd: [APTransportConnectionHTTP.CarPlay-evnt] Event message received
          from 192.168.50.1:5001
airplayd: HTTP Request: POST /command RTSP/1.0
```

The head unit sends `POST /command` events across that link, and their bodies
are `<private>`. So whether the car *asked* for playback, or whether
`com.apple.CarPlayApp` launches Music on connection regardless, is not visible
in the log. Both are consistent with what was captured.

That distinction matters for any fix. If the head unit is requesting a media
source, the behaviour may differ by manufacturer, by wired versus wireless, and
by head-unit setting — and an iOS-side fix may not be the right layer at all.
Nothing here establishes that the result generalises to another car.

## References

- [CarPlay entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
- [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)
- [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
