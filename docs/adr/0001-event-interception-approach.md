# ADR 0001: Event interception approach

- Status: **Rejected** — all four candidates eliminated by measurement.
- Date: 2026-08-05 (proposed), 2026-08-05 (rejected)
- Deciders: repository owner

## Context

A Bluetooth headset tap reaches Music.app along this path (`README.md`):

```text
Bluetooth headset -> bluetoothd -> mediaremoted -> LaunchServices -> Music.app
```

The app must observe the Play/Pause input, attribute it to a specific device,
and drop it — but only for devices the user has selected, and only when it is
certain of the attribution.

The candidates and their trade-offs are in `TECH_RESEARCH.md`. The decisive fact
is that **the layer that can identify the device and the layer that can block
the event are not the same layer**:

- `IOHIDManager` exposes Transport, VID, PID and serial, but cannot consume an
  event.
- `CGEventTap` can consume an event, but a `CGEvent` carries no device identity.
- `kIOHIDOptionsTypeSeizeDevice` can do both, but at whole-interface
  granularity, which risks the volume keys and the microphone.

Two constraints bound the option space: no SIP changes
and no kernel extension, and Bluetooth origin must be established with
confidence rather than inferred, because a false positive breaks the user's
keyboard.

## Decision

**Rejected. None of the four candidates can intercept the event, because the
event does not exist on the path any of them can reach.**

Phase 2 measured it (`TECH_RESEARCH.md` M11): a headset tap produces no HID
device, no HID report and no `NX_SYSDEFINED` event. `bluetoothd` issues a
MediaRemote command directly to `mediaremoted`, which routes it to the Now
Playing destination.

| Candidate | Why it is out |
| --- | --- |
| IOHIDManager | No HID device appears when the earbuds connect; nothing to observe |
| CGEventTap | No event is generated for a tap to intercept |
| IOHID seize | No HID interface exists to seize |
| DriverKit | The path is not a HID path, so a driver does not sit on it |

The evidence is in `TECH_RESEARCH.md` M11: the inventory is byte-identical with
and without the headset connected, the HID monitor logged nothing across the tap
timestamps, and the system log shows the corresponding MediaRemote traffic.

### What survives

`NoBudsMusicCore` is unaffected, as designed. `EventFilter`, `EventSource`,
`DeviceIdentifier` and the rule store are mechanism-agnostic; only
`MediaKeyEventTap` and `HIDDeviceMonitor` are tied to the rejected path.

`HIDDeviceMonitor` should be kept regardless of what replaces this: it is what
produced the negative result, and it is the instrument that would detect a
headset that *does* use HID over GATT.

### What replaces it

Undecided, and it is a specification-level question rather than a technical one.
The only remaining user-space candidate is registering as a Now Playing
destination via `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter` — public API,
sandbox-compatible — but M11 also shows it cannot support per-device rules and
risks absorbing keyboard and Control Center commands. That trade-off needs an
owner decision before any ADR proposes it.

## Evidence required before this ADR can be accepted

1. A headset tap produces a Consumer Control input on `IOHIDManager`, with
   Input Monitoring granted. If it does not, the whole HID-and-tap family is
   eliminated for this device — see the AVRCP hypothesis in `TECH_RESEARCH.md`.
2. That input can be attributed to a Bluetooth device with device-level
   evidence, not timing proximity.
3. The corresponding event is visible to a `CGEventTap`, and the IOHID
   observation can be correlated to it reliably enough to act on.
4. Returning `nil` from the tap callback actually prevents the
   `command requested a launch` line in `just logs-system`.

Record all four in `TECH_RESEARCH.md`, negative results included. A negative
result at step 1 is the most valuable outcome available, because it eliminates
three candidates at once.

## Consequences if CGEventTap + IOHIDManager is accepted

- Requires both Accessibility and Input Monitoring, which is why the App Sandbox
  is currently off. Mac App Store distribution is a stated goal and requires the
  sandbox, so accepting this mechanism forces the question in ADR 0002.
- Direct distribution requires Developer ID signing and notarization.
- The tap callback runs under a system timeout, so the correlation lookup must
  be cheap and synchronous. The rule store is cached in memory for this reason.
- Correlation is inherently a race. Every unresolved case must fail open.

## Consequences if it is rejected

- `MediaKeyEventTap` and the future IOHID monitor are replaced;
  `NoBudsMusicCore` is not. `EventFilter`, `EventSource`, `DeviceIdentifier` and
  the rule store are mechanism-agnostic by design, so this ADR can be reopened
  without a rewrite.
- The next candidates, in order, are interface-level exclusive access, then
  seize, then DriverKit.
- If the AVRCP hypothesis holds, none of those help, and the project has no
  user-space blocking answer. That is a result to report, not to work around.
  The Now Playing routing idea in `TECH_RESEARCH.md` would then need an explicit
  decision, because it trades against success criterion 10. Note that it is also
  the only candidate that is unambiguously App Store compatible (ADR 0002), so
  the store intent is a reason to measure it earlier than "last resort" implies.

## Alternatives rejected outright

- **Quit Music.app after it launches** (the noTunes approach). Explicitly
  rejected: the launch itself is the problem.
- **Disable `com.apple.rcd`.** Already tried; the behaviour persists.
- **Disabling SIP, a kernel extension, or stopping `bluetoothd` /
  `mediaremoted`.** Non-goals.
- **DriverKit as a starting point.** Only after user space is proven
  insufficient.
