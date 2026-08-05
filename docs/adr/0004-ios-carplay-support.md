# ADR 0004: iOS is another target, not another repository

- Status: **Accepted** — same repository, separate build target.
- Date: 2026-08-05
- Deciders: repository owner

## Context

The same bug exists on iOS. Measured on iPhone 16 Pro, iOS 27.0, with a
Bluetooth headset — `docs/ios-carplay-music-autolaunch.md` has the log:

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play, SenderBundleIdentifier = <com.apple.BTAvrcp>>,
              and command requested a launch.
```

That is the macOS line word for word, preceded by the same `No context for
context-sensitive command`. The cause is identical: no Now Playing destination,
so the system launches one.

The investigation began as a CarPlay question, and a headset tap on a locked
phone reproduces *a* version of it with no car involved. Connecting to a car was
then measured too, and it turned out to be a different mechanism: no launch
request is issued at all, and `com.apple.CarPlayApp` launches Music itself.

So there are two separate problems that look like one. The headset case is
understood and matches macOS. The CarPlay case — the one this started from —
is not explained by it.

## Decision

**iOS becomes another target in this repository. The macOS app is unchanged.**

The measured differences between the two systems turn out not to reach the
implementation:

| Difference | Effect on the code |
| --- | --- |
| Sender is `com.apple.BTAvrcp`, not `bluetoothd` | None. The app never inspects the sender |
| Commands carry `kMRMediaRemoteOptionSourceID` | None. Reading it needs private API, so it is not used |
| iOS may not allow silent indefinite residency | Unmeasured. May vanish entirely — see below |

Two of the three do not touch the code at all, and the third is a hypothesis.
The source layout already splits along the right line:

- `NoBudsMusicCore` imports `Foundation` only, so it is portable as it stands.
- `NowPlayingSink` is portable apart from `renderNote()`, roughly twenty lines
  of `NSImage` drawing that becomes `UIImage`.
- `StatusItemController`, `AppDelegate`, `SingleInstance` and `main` are the
  platform shell, and a menu bar item has no iOS counterpart anyway.

That is a target boundary, not a repository boundary.

## Options considered

### A. Separate repository for iOS

Rejected, having first been accepted and then reconsidered. The case for it
rested on differences that do not affect the code, plus one that has not been
measured. Splitting on a predicted divergence, before the divergent code exists,
is the speculative future-proofing ADR 0003 refused when it deleted 1,400 lines
rather than keep them against a headset that might use HID over GATT. The same
argument applies to repositories.

It also doubles the release process, the CI setup and the documentation for one
developer, and separates the iOS notes from the macOS measurements they are
defined against.

### B. Separate target in this repository

**Accepted.** `project.yml` already carries three targets; a fourth costs a
platform key. The shared module is genuinely shared, and the parts that cannot
be shared are the parts that were never going to be.

### C. Use the private switch instead of an app

Not available.
`AVSystemController_ShouldIgnorePlayCommandsFromAccessoryAttribute` does exactly
what is wanted, and is private, undocumented, and unusable in anything shipping
through the App Store. No user-facing setting maps to it.

## Consequences

- `NoBudsMusicCore` and `NowPlayingSink` become the shared surface. Keeping them
  free of AppKit is now a constraint rather than a coincidence.
- The macOS app gains nothing and loses nothing. No audio session, no
  entitlement, no behaviour change.
- **The approach works and is blocked on residency, not on capability.**
  Measured in the car: with the app holding the Now Playing slot, connecting
  launches no Music and plays no audio, and the CarPlay dashboard shows this app
  instead. One button press holds the slot for at least twelve minutes.
- **It is not a product until it holds that slot without being opened by hand.**
  Pressing a button before every drive is no better than stopping Music in
  CarPlay, which is what people already do. iOS offers no public way to wake a
  terminated app when a car connects: route-change notifications need the app
  alive, CoreBluetooth background restoration is BLE-only, and waking on
  location to detect a car is not something to put in front of review.
- **The intended route is the CarPlay audio entitlement**, which has the system
  launch the app on connection. That makes this an app that plays silence and
  appears among the car's audio apps — the "make Spotify the app you last played
  from" workaround, with an app that plays nothing. Whether Apple accepts that
  under guideline 2.5.4 is the open question, and it is a question about review
  rather than about whether the mechanism works.
- Applying needs the Developer Program enrolment that is still processing. If
  the entitlement is refused, iOS ends here: the cause is documented, the fix is
  demonstrated, and there is no public way to run it unattended. That is a
  result worth having recorded either way.
- If it is granted, revisit option A. An audio session, a background mode and a
  CarPlay entitlement are three things the macOS app has no use for, and at that
  point the divergence is measured rather than predicted.
- One finding applies back to macOS and is worth measuring separately: iOS keeps
  the destination across taps without the holder continuing to play. If macOS
  behaves the same, the app may not need to declare `.playing` indefinitely,
  which is what puts it in Control Center at all times. That is a measurement,
  not a plan; ADR 0003 stands until it is made.

## A trap worth naming

`kMRMediaRemoteOptionSourceID` carries the headset's Bluetooth address, so iOS
appears to make per-device rules possible where ADR 0003 found them impossible.
It is visible in the log and absent from public API: `MPRemoteCommandEvent`
exposes `command` and `timestamp` and nothing else.

If per-device behaviour is ever wanted, the public route is the audio route —
`AVAudioSession.currentRoute.outputs` gives `uid`, `portName` and `portType` for
the connected device. A headset tap can only arrive while that headset is the
output, so the current route answers the question the command cannot. Untested,
and recorded here so that the private call is not reached for first.
