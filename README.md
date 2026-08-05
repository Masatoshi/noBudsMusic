# noBudsMusic

Stops Music.app from launching itself when you tap a Bluetooth headset.

[日本語](README.ja.md)

## The problem

On macOS 26, tapping a Bluetooth headset can open Music.app even when nothing
was playing and you never asked for it:

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play, SenderBundleIdentifier = com.apple.bluetoothd>,
              and command requested a launch.
```

Disabling `com.apple.rcd` does not help.

## How it works

**This app blocks nothing.**

`bluetoothd` sends the tap to `mediaremoted` as a MediaRemote command, which
routes it to whatever holds the Now Playing destination — and launches a player
when nothing does. That empty slot is the bug.

So the app occupies the slot and gets out of the way. Every command it receives
is answered with `.noSuchContent`:

```text
something is playing   → mediaremoted passes the command to it, as normal
nothing is playing     → the command goes nowhere, and no launch is requested
```

Answering `.success` would also prevent the launch, but it consumes the command,
and then a paused YouTube tab can no longer be resumed from the headset. That one
return value is the whole design; it took eight measured dead ends to find.

Consequences:

- **No permissions.** No Accessibility, no Input Monitoring, no event tap.
- **No polling.** No timer and no observer loop; the app is woken only when a
  command arrives.
- **Runs sandboxed**, with nothing degraded.
- **Media and volume keys are unaffected**, because everything is forwarded.
- **No per-device settings**, and there cannot be: a MediaRemote command carries
  no device identity. Every headset arrives as `com.apple.bluetoothd`.

## Install

Requires macOS 14+, though it is only tested on macOS 26 / Apple Silicon.

```bash
just run
```

Build prerequisites: Xcode 26, [just](https://github.com/casey/just),
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

There are no signed releases yet; building it is the only way to run it. See
[ADR 0002](docs/adr/0002-distribution-channel.md) for why, and what would change
that.

## Using it

A menu bar item and nothing else. No windows.

```text
Prevent Music.app from launching   [x]
Show in Menu Bar                   [x]
Launch at Login                    [ ]
Quit
```

Hiding the menu bar item keeps the app running. To bring it back, open the app
again from the Finder or Spotlight, or run `just show`.

While the app holds the slot and nothing else is playing, Control Center lists it
as *Preventing Music.app from launching*. That is unavoidable — occupying the Now
Playing slot means appearing in Now Playing — and it is accurate, because at that
moment the app really is the destination. When something is playing, that app is
shown instead.

## Verified behaviour

Tested on two machines with Redmi Buds 6 Lite and Pixel Buds A-Series:

- Tapping the earbuds does not launch Music.app
- YouTube and Amazon Music stay controllable from the earbuds once they have
  played
- A real player takes the destination back while it plays
- Keyboard media keys (F8) and volume keys (F11/F12) are unaffected
- Volume, microphone and AirPlay are unaffected
- The app stays resident with the menu bar item hidden, survives restart, and
  does not launch twice

## Relationship to noTunes

[noTunes](https://github.com/tombonez/noTunes) solves a broader problem: it stops
Music.app from opening whatever caused it — clicking the icon, following a link,
a headset tap, anything.

This app addresses one specific cause. It removes the condition that makes
`mediaremoted` launch a player, and does nothing about any other route into
Music.app.

So they are not really substitutes. If you want Music.app never to open, noTunes
covers far more ground. If the only time it opens is when you tap your earbuds,
this is a narrower fix that needs no permissions and nothing running at rest.

## Documentation

| File | What it is |
| --- | --- |
| [`docs/macos-notes.md`](docs/macos-notes.md) | macOS behaviour found the hard way. Useful outside this project |
| [`TECH_RESEARCH.md`](TECH_RESEARCH.md) | The measurement log, M1-M27, negative results included |
| [`docs/adr/`](docs/adr/) | Three decisions: the interception mechanism, distribution, the Now Playing sink |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Layout and design constraints |

The interesting part is what did **not** work. IOHIDManager, CGEventTap,
`kIOHIDOptionsTypeSeizeDevice` and DriverKit were all eliminated by measurement:
a Bluetooth headset tap never touches the HID path at all. So were per-device
rules, and three other shapes of the Now Playing approach. `TECH_RESEARCH.md` has
the evidence for each.

## Development

`project.yml` is the source of truth; `noBudsMusic.xcodeproj` is generated and
not committed.

```bash
just check   # lint, build, test
just logs    # what the app is doing
just --list  # everything else
```

To sign with a real certificate instead of ad-hoc, put this in `.env`
(gitignored):

```bash
NOBUDS_CODE_SIGN_IDENTITY="<certificate SHA-1>"   # security find-identity -v -p codesigning
NOBUDS_DEVELOPMENT_TEAM="<team id>"
```

Without it the build is ad-hoc signed, which is fine — the app needs no
permissions, so there is no TCC grant to lose when the signature changes.

## License

MIT
