# Roadmap

Phases follow the implementation brief. Each phase ends with a build and a
report; measurement phases end with a result recorded in `TECH_RESEARCH.md`,
including negative results.

## Phase 1 - Skeleton (done)

- Menu bar app, resident, no Dock icon (SwiftUI at first; replaced by AppKit in
  Phase 4 after three CPU spins)
- Global on/off toggle
- Settings persistence
- Per-device rule model, identity, and storage
- Devices screen
- Diagnostics screen with permission status
- Single-instance handling and the hidden-menu-bar recovery path

## Phase 2 - Observation (done)

- IOHIDManager device enumeration
- Bluetooth determination from the `Transport` property
- Consumer Control event logging with source device, usage page, usage
- Observed with Pixel Buds A-Series connected

**Answer: no.** A headset tap is not visible on the HID path. `bluetoothd`
issues a MediaRemote command directly. See `TECH_RESEARCH.md` M11 and
`docs/adr/0001-event-interception-approach.md`, now Rejected.

## Phase 3 - Blocked, needs a decision

The original plan is void. All six steps below assumed the event reaches a HID
or event-tap layer, and M11 shows it does not.

1. ~~Identify the source device with IOHIDManager~~
2. ~~Block the corresponding event with CGEventTap~~
3. ~~Determine whether CGEventTap can attribute the event to a device~~
4. ~~Exclusive access at the Consumer Control interface level~~
5. ~~`kIOHIDOptionsTypeSeizeDevice`~~
6. ~~DriverKit~~

The only remaining user-space candidate is becoming a Now Playing destination
(`MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`). It cannot support
per-device rules and risks absorbing keyboard and Control Center commands, so it
needs an owner decision — and a measurement of whether a fallback-only
destination is possible — before it becomes a phase.

## Phase 4 - Integration

- Wire per-device rules to the blocking path
- Permission guidance
- Launch at login
- Menu bar hiding and the recovery path
- Validation on real hardware against the 14 success criteria in `README.md`

## After Phase 4 - Distribution

Only once the app actually works. Nothing here constrains Phases 1-4.

- Re-run the manual matrix with `com.apple.security.app-sandbox` enabled and
  record both results in `TECH_RESEARCH.md`
- Decide ADR 0002: App Store, or open source on GitHub with direct distribution
- Signing for the chosen channel
