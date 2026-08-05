# Architecture

## Overview

```text
Bluetooth headset -> bluetoothd -> mediaremoted -> Now Playing destination
                                                          ^
                                                          |
                                             noBudsMusic holds it and
                                             discards Play/Pause
```

There is no interception. The app is not in the path; it *is* the destination.
See `docs/adr/0003-now-playing-sink.md` and `TECH_RESEARCH.md` M11.

## Two Layers

**`NoBudsMusicCore`** — a static library with no AppKit or MediaPlayer
dependency. Everything that *decides* lives here, so it is unit-testable without
a running app or a paired headset.

**`NoBudsMusic`** — the app. Menu bar UI, the Now Playing sink, login item.

## Data Flow

1. `MPRemoteCommandCenter` delivers a command.
2. `EventFilter` decides: Status ON and Play/Pause -> absorb, otherwise forward.
3. `NowPlayingSink` logs the decision and its reason.
4. The handler returns `.success` (absorbed) or `.noSuchContent` (forwarded).

No device dimension exists at any step. MediaRemote does not carry one.

## Module Mapping

| Component | File |
| --- | --- |
| App entry, menu bar | `Sources/NoBudsMusic/NoBudsMusicApp.swift` |
| App state | `Sources/NoBudsMusic/AppModel.swift` |
| The mechanism | `Sources/NoBudsMusic/NowPlayingSink.swift` |
| Single instance | `Sources/NoBudsMusic/SingleInstance.swift` |
| Launch at login | `Sources/NoBudsMusic/LaunchAtLogin.swift` |
| Decision rule | `Sources/NoBudsMusicCore/EventFilter.swift` |
| Command vocabulary | `Sources/NoBudsMusicCore/MediaKey.swift` |
| App settings | `Sources/NoBudsMusicCore/AppSettings.swift` |
| Identity | `Sources/NoBudsMusicCore/AppIdentity.swift` |

## Removed

HID enumeration, the event tap, device identity and per-device rules were
deleted after `TECH_RESEARCH.md` M11 showed the event never reaches those
layers. They are in the first commit if the measurement ever needs redoing.

## Design constraints

**Passive.** The app registers a destination once and is woken only when a
command arrives. No timer, no observer loop, no cost at rest. That is the main
advantage over noTunes and must not be spent on a polling fix for M18.

**No permissions.** `MPRemoteCommandCenter` is not gated by TCC. The app needs
neither Accessibility nor Input Monitoring.

**No windows.** The app is a menu bar item and nothing else. Diagnostics live in
`just logs`. A SwiftUI-hosted window in a `MenuBarExtra`-only app was one of two
ways found to pin the main thread; the other was persisting an unchanged value
from a binding. See `docs/macos-notes.md`.

**Localised.** English base, Japanese in `Resources/ja.lproj`. Menu strings are
keys, not literals.
