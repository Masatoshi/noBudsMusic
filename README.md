# noBudsMusic
![noBudsMusic icon](assets/no-buds-music-icon.png)

Stops Music.app from launching itself when you tap a Bluetooth headset.

[日本語](README.ja.md)

## The problem

On macOS 26, tapping a Bluetooth headset can open Music.app even when nothing
was playing and you did not intend it:

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play, SenderBundleIdentifier = com.apple.bluetoothd>,
              and command requested a launch.
```

Disabling `com.apple.rcd` does not help.

The launch itself can be disruptive even if Music is closed immediately. For
example, when Music has a Screen Time App Limit, an unintended launch can
trigger the limit alert. This app addresses the launch request itself, not just
whether Music remains open afterwards.

## How it works

**This app blocks nothing.**

It does not intercept Play/Pause. It simply acts as the Now Playing destination.

`bluetoothd` sends the tap to `mediaremoted` as a MediaRemote command, which
routes it to the Now Playing destination. When there is no destination, macOS
launches a player. That is what leads to Music.app opening by itself.

Once this app is the destination, there is no such case, so no launch is
requested. Every command it receives is answered with `.noSuchContent`, so
whatever is actually playing still gets it.

Answering `.success` would also prevent the launch, but it consumes the command,
and then a paused YouTube tab can no longer be resumed from the headset. That one
return value is the key to the design; eight other approaches were rejected by
measurement before it.

Consequences:

- **Runs entirely within the App Sandbox, so no additional permissions are
  needed.** No Accessibility, no Input Monitoring, no event tap.
- **No polling.** No timer and no observer loop; the app is woken only when a
  command arrives.
- **Media and volume keys are unaffected.** It only ever answers
  `.noSuchContent`, so existing behaviour is unchanged.
- **No per-device settings**, and there cannot be: a MediaRemote command carries
  no device identity. Every headset arrives as `com.apple.bluetoothd`.

## Install

May work on macOS 14 and later; only tested on macOS 26 / Apple Silicon.

### Mac App Store

The store page may take time to appear in every region while Apple completes
the release rollout.

[Get noBudsMusic on the Mac App Store](https://apps.apple.com/us/app/nobudsmusic/id6800704078)

### Homebrew

The tap is published:

```bash
brew tap masatoshi/noBudsMusic
brew install --cask no-buds-music
```

Homebrew 6 may ask you to trust a third-party tap before it will load the cask.
If it does, run `brew trust --cask masatoshi/nobudsmusic/no-buds-music`.

The cask installs the Developer ID-signed and notarized build published on
GitHub Releases. See [ADR 0002](docs/adr/0002-distribution-channel.md) for the
distribution reasoning.

### Build from source

Development requires Xcode 26 and two build tools:

```bash
brew install just xcodegen
just run
```

The app appears in the menu bar; there is no window and no Dock icon.

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

While the app holds the Now Playing destination and nothing else is playing,
Control Center lists it as *Preventing Music.app from launching*. That is
unavoidable — being the Now Playing destination means appearing in Now Playing —
and it is accurate, because at that moment the app really is the destination.
When something is playing, that app is shown instead.

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

[noTunes](https://github.com/tombonez/noTunes) and noBudsMusic address related
but different needs. noTunes is designed to keep Music.app from opening across
a broad range of launch paths and can optionally redirect a launch to another
player. It is a good fit when you do not want Music to open at all.

noBudsMusic focuses narrowly on unintended Bluetooth media commands. It uses a
different mechanism: it supplies a Now Playing destination before Music is
requested, rather than acting on Music after the launch begins. Intentional
launches of Music still work.

This distinction matters when the launch itself has an effect, such as
triggering a Screen Time App Limit alert. Choose noTunes for broad launch
prevention, or noBudsMusic when you want to keep intentional Music use while
preventing this specific Bluetooth-triggered case.

## Documentation

| File | What it is |
| --- | --- |
| [`docs/macos-notes.md`](docs/macos-notes.md) | macOS behaviour observed during development. Applies outside this project |
| [`TECH_RESEARCH.md`](TECH_RESEARCH.md) | Measurement log, M1-M27, negative results included |
| [`docs/adr/`](docs/adr/) | Four decisions: the interception mechanism, distribution, the Now Playing sink, iOS/CarPlay |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Layout and design constraints |

**The approaches that did not work are recorded too.** IOHIDManager, CGEventTap,
`kIOHIDOptionsTypeSeizeDevice` and DriverKit were all eliminated by measurement:
a Bluetooth headset tap never touches the HID path at all. So were per-device
rules, and three other forms of the Now Playing approach. `TECH_RESEARCH.md` has
the evidence for each.

## Development

`project.yml` is the project definition. `noBudsMusic.xcodeproj` is generated
from it, so it is not in the repository; the build recipes regenerate it each
time.

```bash
just check   # lint, build, test
just logs    # what the app is doing
just --list  # everything else
```

Builds are ad-hoc signed. That is fine for development — the app requests no
additional permissions, so there is no grant to lose when the signature changes.

## License

MIT
