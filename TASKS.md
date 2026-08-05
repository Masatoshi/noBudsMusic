# Implementation Tasks

Status: done / partial / todo.

## Phase 1 - Skeleton

- done: Xcode project generated from `project.yml`
- done: SwiftUI menu bar app, accessory activation policy
- done: Global Status ON/OFF with persistence
- done: Device identity model and stable identifier tiers
- done: Per-device rule storage
- done: Devices screen
- done: Diagnostics screen, including permission status
- done: Single-instance handling, URL scheme, reopen handling
- done: Launch at login via ServiceManagement

## Phase 2 - Observation

- done: Enumerate HID devices with IOHIDManager
- done: Populate the Devices screen from live enumeration
- done: Log Consumer Control input with source device, usage page, usage
  (monitor running and observing 1 device; no input observed yet)
- done: Observe Pixel Buds A-Series — no HID device, no HID input
- done: Record the result in `TECH_RESEARCH.md` (M1-M11)

## Phase 3 - Void

ADR 0001 is Rejected; every task here assumed a HID or event-tap path.

- n/a: Attribute an event to a device
- n/a: Block with CGEventTap
- n/a: Determine whether CGEventTap can attribute a source
- n/a: Consumer Control interface-level exclusive access
- n/a: `kIOHIDOptionsTypeSeizeDevice` and its side effects
- done: Decide ADR 0001 — Rejected

## Now Playing sink (ADR 0003)

- done: Claim the destination with public API (M12)
- done: Release and reclaim on Status toggle (M13)
- done: Absorb the headset tap; Music.app does not launch (M15)
- done: Real players take the destination back without interference (M17)
- todo: **Reclaim the destination when it becomes free** (M18) — without
  stealing it from a playing app
- todo: Verify a keyboard media key is not swallowed (ADR 0003 risk 2)
- todo: Decide what Control Center should display (M14)

## Next - needs an owner decision

- todo: Decide whether to pursue the Now Playing destination approach, given
  that it cannot support per-device rules
- todo: If pursued, measure whether a fallback-only destination is possible
  (absorbing the launch-causing command without absorbing keyboard and Control
  Center commands)

## Phase 4 - Integration

- todo: Connect per-device rules to the blocking path
- todo: Permission guidance end to end
- done: Validate the success criteria on real hardware (two machines)

## Distribution (ADR 0002)

The app works, so this is now actionable.

- done: Enable `com.apple.security.app-sandbox`, rebuild, run the matrix
- done: `MPNowPlayingInfoCenter` still wins the destination sandboxed (M26)
- done: `DistributedNotificationCenter` removed rather than app-group-prefixed;
  the handshake goes through the URL scheme
- done: `SMAppService` login item registers sandboxed
- done: Headset tap, Control Center artwork verified on the sandboxed build
- todo: Decide ADR 0002 (App Store vs OSS on GitHub)
- todo: Signing for the chosen channel
- todo: If GitHub, translate `README.md` to English
