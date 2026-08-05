# Architecture

## Overview

```text
Bluetooth headset -> bluetoothd -> mediaremoted -> ??? -> Music.app
                                        ^
                                        |
                        noBudsMusic observes here (Phase 2)
                        and blocks here (Phase 3), if it can
```

Where exactly the app can intervene is undecided. See
`docs/adr/0001-event-interception-approach.md` and `TECH_RESEARCH.md`.

## Two Layers

**`NoBudsMusicCore`** — a static library with no AppKit, CoreGraphics, or IOKit
dependency. Everything that *decides* lives here, so it is unit-testable without
a running app, a paired headset, or a permission grant.

**`NoBudsMusic`** — the app. Menu bar UI, event plumbing, permissions, login
item. It does plumbing; it does not decide.

Blocking rules live in `NoBudsMusicCore.EventFilter` and nowhere else. This is
the boundary that lets the interception mechanism be replaced without touching
the rules, which matters because the mechanism is still an open question.

## Data Flow

1. Observe a media key event.
2. Resolve the event to a source device (`EventSourceResolving`).
3. Look up that device's rule (`DeviceRuleStoring`).
4. Decide (`EventFilter`): global Status AND Bluetooth AND rule on -> block.
5. Record the decision and its reason (`DiagnosticsLog`).
6. Anything less than a confident yes at step 2 passes through.

Step 2 is unimplemented. `UnidentifiedSourceResolver` always returns
`.unidentified`, so step 4 never blocks. That is the Phase 2/3 boundary, not a
placeholder to be worked around.

## Module Mapping

| Component | File |
| --- | --- |
| App entry, menu bar | `Sources/NoBudsMusic/NoBudsMusicApp.swift` |
| App state | `Sources/NoBudsMusic/AppModel.swift` |
| Devices screen | `Sources/NoBudsMusic/Views/DevicesView.swift` |
| Diagnostics screen | `Sources/NoBudsMusic/Views/DiagnosticsView.swift` |
| Settings window host | `Sources/NoBudsMusic/Views/SettingsWindowController.swift` |
| Event tap (Phase 3) | `Sources/NoBudsMusic/MediaKeyEventTap.swift` |
| Permissions | `Sources/NoBudsMusic/Permissions.swift` |
| Single instance | `Sources/NoBudsMusic/SingleInstance.swift` |
| Launch at login | `Sources/NoBudsMusic/LaunchAtLogin.swift` |
| Decision rules | `Sources/NoBudsMusicCore/EventFilter.swift` |
| Media key classification | `Sources/NoBudsMusicCore/MediaKey.swift` |
| Source attribution types | `Sources/NoBudsMusicCore/EventSource.swift` |
| Device identity | `Sources/NoBudsMusicCore/DeviceIdentity.swift` |
| Per-device rules | `Sources/NoBudsMusicCore/DeviceRule.swift`, `DeviceRuleStore.swift` |
| Devices list merge | `Sources/NoBudsMusicCore/DeviceList.swift` |
| App settings | `Sources/NoBudsMusicCore/AppSettings.swift` |
| Diagnostics log | `Sources/NoBudsMusicCore/DiagnosticsLog.swift` |
| Permission model | `Sources/NoBudsMusicCore/PermissionStatus.swift` |

## Device Identity

A device name alone is not a persistent identifier. `DeviceIdentifier.make`
builds the strongest available, in fixed priority:

1. `serial` — vendor + product + serial number. Unique per physical unit.
2. `vendorProduct` — vendor + product + name. Cannot distinguish two of the same
   model.
3. `fallback` — transport, manufacturer, name, vendor, product, usage page,
   usage.

Location ID is collected for diagnostics but excluded from the identifier: it
changes across reconnects, which would orphan the saved rule every time.

Tiers 2 and 3 are `isCollisionProne`. That is surfaced in the log when a rule is
saved and in the Devices screen, per the brief.

## Concurrency

`AppModel` is `@MainActor`. The event path is not and cannot be: a tap callback
must decide synchronously, under a system timeout, so it cannot await a hop to
the main actor. Everything the callback touches — `DiagnosticsLog`,
`DeviceRuleStoring`, the enabled flag — is lock-guarded and `Sendable`.
