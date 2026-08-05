# Technical Research

Measured results go here, including negative ones. A negative result is the more
valuable outcome: it eliminates a candidate.

Nothing below the "Candidates" section has been measured yet.

## The Central Problem

The layer that can **identify** the source device and the layer that can
**block** the event are not the same layer.

| Candidate | Sees the event? | Identifies the device? | Can block? | Cost |
| --- | --- | --- | --- | --- |
| IOHIDManager | Unmeasured | Yes — Transport, VID, PID, serial | No, except by seizing | Medium |
| CGEventTap | Unmeasured | **No** — a `CGEvent` carries no HID device | Yes, for what it sees | Low |
| IOHID seize | n/a | Yes | Yes, but takes the whole interface | Medium, with side effects |
| DriverKit | Yes | Yes | Yes | High; system extension, distribution burden |

Store viability differs sharply between these; see ADR 0002.

Per-device blocking therefore requires correlating an IOHID observation with a
CGEventTap callback. Whether that correlation is reliable is the Phase 3
question. Where it is not, the event is passed through — see the safety property
in this project's goals.

## CONFIRMED: the event is not on the HID path

**Status: measured 2026-08-05. See M11.** The hypothesis below was correct.

The confirmed log line is:

```text
SenderBundleIdentifier = <com.apple.bluetoothd>
command = Play
Destination app com.apple.Music not available for command
command requested a launch
```

`bluetoothd` being the *sender* of a MediaRemote command is consistent with an
AVRCP passthrough command being forwarded directly to `mediaremoted`, rather
than a HID report being translated into an `NX_SYSDEFINED` event.

If that is what is happening, then for the affected device:

- IOHIDManager observes nothing
- CGEventTap sees no event to block
- seize has no HID interface to take
- DriverKit does not help either, because the path is not a HID path

Some headsets use HID over GATT instead, so the two test devices may behave
differently. Phase 2 decides this.

### What would confirm or refute it

1. Run the app with Input Monitoring granted; tap the headset. If no Consumer
   Control input arrives for that device, the HID path is not carrying it.
2. Run `just logs-system` during the same tap. `bluetoothd` and `mediaremoted`
   activity with no corresponding HID input is the AVRCP signature.
3. Compare against a keyboard Play/Pause, which should appear on the HID path.

### If confirmed

The remaining public-API idea is to stop being a blocking problem and become a
routing one: register the app as a Now Playing destination via
`MPRemoteCommandCenter` / `MPNowPlayingInfoCenter` so the Play command has
somewhere to go and never reaches `Destination app not available`.

This conflicts with success criterion 10 ("do not needlessly break Control
Center's Now Playing") and is not to be implemented without an explicit
decision.

It is, however, the only candidate that needs no TCC grant and no sandbox
exception — which makes it the only one that is unambiguously Mac App Store
compatible. Since store distribution is a stated goal, that is a reason to
measure it earlier than its "last resort" position suggests. See
`docs/adr/0002-distribution-channel.md`.

## Candidates

### IOHIDManager

Role: observation and identification.

- Enumerates devices and exposes Transport, Product Name, Manufacturer, Vendor
  ID, Product ID, Serial Number, Location ID, Primary Usage Page, Primary Usage.
- Requires Input Monitoring to receive input values. Without it,
  `IOHIDManagerOpen` succeeds and no values arrive — a silent failure.
- Cannot consume an event.

### CGEventTap

Role: blocking.

- `.defaultTap` on `NX_SYSDEFINED` can drop an event by returning `nil`.
- Requires Accessibility. Without it `CGEvent.tapCreate` returns `nil`, again
  silently.
- Carries no device identity.
- The callback runs under a system-enforced timeout; exceeding it disables the
  tap. Any correlation lookup must be cheap and synchronous.

### IOHID seize (`kIOHIDOptionsTypeSeizeDevice`)

Role: last resort before DriverKit.

- Takes exclusive access to a device, so its input stops reaching the system.
- Granularity is the concern: if Play/Pause and volume share an interface,
  seizing costs the volume keys unless the app re-injects them, which is a large
  and fragile step.
- Unmeasured whether the Consumer Control interface can be seized separately.

### DriverKit

Not to be used before the above are ruled out. A system extension raises the
distribution and trust burden considerably, and does not help at all if the
AVRCP hypothesis holds.

## Measured Results

### 2026-08-05 — HID inventory, no headset connected

Environment: macOS 26.5.2, Apple Silicon, ad-hoc signed debug build.
Bluetooth connected at the time: **Adv360 Pro keyboard (BLE) only. No headset.**

Test devices available: Redmi Buds 6 Lite and **Pixel Buds A-Series**. The
original brief named Pixel Buds Pro; A-Series is what is actually on hand and is
a different product, so any result recorded here applies to A-Series only.

**M1. Enumeration works without Input Monitoring.** `IOHIDManagerCopyDevices`
returned 12 devices with the grant denied. Only input *values* require it.

**M2. Input values do not arrive without Input Monitoring.**
`IOHIDManagerOpen` returned `-536870174` (`kIOReturnNotPermitted`) with
`IOHIDCheckAccess` reporting `denied`. This is the silent-failure mode the brief
warns about: without the explicit check, the app would have looked like it was
observing and finding nothing.

**M3. Inventory.**

| Device | Transport | VID | PID | Serial | Usage | Tier |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | SPU | - | - | none | 65280/255 | 3 |
| Apple | SPU | - | - | none | 65292/1 | 3 |
| Apple | SPU | - | - | none | 65292/5 | 3 |
| BTM | SPMI | - | - | none | 65280/72 | 3 |
| Kensington Slimblade Trackball | USB | 0x047D | 0x2041 | none | 1/2 | 2 |
| Kensington Slimblade Trackball | USB | 0x047D | 0x2041 | none | 255/1 | 2 |
| Adv360 Pro | **Bluetooth** | 0x1D50 | 0x615E | none | 1/6 | 2 |
| TouchBarUserDevice | Virtual | 0x05AC | 0x8600 | none | 1/6 | 2 |
| Karabiner DriverKit VirtualHIDKeyboard 1.8.0 | Unknown | 0x05AC | 0x024F | **present** | 1/6 | 1 |
| Karabiner DriverKit VirtualHIDPointing 1.8.0 | Unknown | 0x16C0 | 0x27DA | **present** | 1/2 | 1 |
| USB2.0 HID | USB | 0x0BDA | 0x1100 | none | 65498/218 | 2 |
| **Headset** | **Audio** | - | - | none | **12/1** | **3** |

**M4. A Consumer Control device exists with no headset connected.** The last
row — usage page 12 (0x0C, Consumer), usage 1 (Consumer Control) — is the media
control interface, and it was present while no Bluetooth headset was paired.
Its role is unknown: it may be the audio subsystem's generic control interface,
or it may be where a connected headset's taps arrive. **Do not assume either.**
The comparison with the headset connected is what decides it.

Note its `Transport` is `Audio`, not `Bluetooth`.

**M5. The only keyboard on this machine is Bluetooth.** The Adv360 Pro is a BLE
keyboard. Confirms that "block Bluetooth devices" as a category would be
actively dangerous here, and that per-device rules are load-bearing rather than
a nicety.

**M6. Karabiner-Elements is installed** and presents two DriverKit virtual HID
devices. It can intercept and re-emit keyboard input, so it is a potential
confounder for Phase 3 — an event may be Karabiner's re-emission rather than the
original. It is also a working existence proof that DriverKit virtual HID is
viable on this machine, should ADR 0001 ever get that far.

**M7. Identifier tiers in practice.** Only the two Karabiner virtual devices
report a serial number (tier 1). Every piece of real hardware here is tier 2 or
3. The `Headset` device is tier 3 with no VID or PID, so its identifier is built
from transport, name and usage alone.

### 2026-08-05 — Opening the devices

**M8. `IOHIDManagerOpen` is all-or-nothing and fails on contested devices.**
With the manager matching every device, open returned `kIOReturnExclusiveAccess`
(`-536870203`) *even with Input Monitoring granted*. Narrowing the match to
Consumer-page devices did not help either — the manager-level open still failed.

Opening each device individually with `IOHIDDeviceOpen` succeeds. The whole
manager was being failed by devices this app never needed.

Which process holds the contested devices is not established. Karabiner-Elements
is the leading suspect (it seizes keyboards, and its two DriverKit virtual
devices are in the inventory), but it was not isolated to confirm.

**M9. Exactly one Consumer-page device exists on this machine.** The `Headset /
Audio / 12 / 1` device from M4. It opens without complaint and is now being
observed. `0 refused`.

**M10. Consequence: the Bluetooth keyboard is not observed.** The Adv360 Pro has
primary usage `1/6` (keyboard), so it is outside the Consumer-page match. Media
keys arriving as a Consumer *collection* inside a keyboard device would not be
seen. Accepted for now — widening the match reintroduces the exclusivity problem
— but it means "the keyboard is unaffected" cannot be verified on the HID path.

**Relevant to Phase 3:** exclusive-access contention already exists on this
machine. Any seize-based approach has to coexist with whatever is holding those
devices.

### 2026-08-05 — M11. The decisive measurement

**A headset tap produces no HID input and no new HID device. It arrives as a
MediaRemote command sent by `bluetoothd`.**

Setup: Pixel Buds A-Series connected, HID monitor running and observing the
`Headset / Audio / 12 / 1` device, Input Monitoring granted.

Result 1 — **the earbuds present no HID interface at all.** The inventory with
the earbuds connected is byte-identical to the inventory with no headset
connected: 12 devices, same names, same properties. Nothing appears on connect.

Result 2 — **the HID monitor recorded nothing during the taps.** Zero entries in
the app's log across the tap timestamps.

Result 3 — **the taps are visible in the system log, as MediaRemote commands.**

```text
10:21:27.443  bluetoothd: (MediaRemote) Request: Command = <Play>,
              SenderDevice = <Mac>, SenderBundleIdentifier = <com.apple.bluetoothd>,
              SenderPID = <429>
10:21:27.445  mediaremoted: Received command from client
              <MRDMediaRemoteClient, bundleIdentifier = com.apple.bluetoothd,
              pid = 429, entitlements=512>: command = Play
10:21:27.446  mediaremoted: Sending command ... command = Play
              -> 【 LOCL (Mac) > com.apple.Music (54644) > Music 】
```

`bluetoothd` is the *client* issuing a MediaRemote command. There is no HID
report and no `NX_SYSDEFINED` event anywhere in the chain.

A `NextTrack` and a `PreviousTrack` command were observed the same way, so the
whole gesture set takes this path, not just Play.

### What M11 eliminates

| Candidate | Status |
| --- | --- |
| IOHIDManager | **Eliminated.** No HID device, no HID report to observe |
| CGEventTap | **Eliminated.** No event is generated for a tap to see |
| IOHID seize | **Eliminated.** No HID interface exists to seize |
| DriverKit | **Eliminated.** The path is not a HID path at all |

All four candidates in the original brief are gone. This is the negative result
Phase 2 existed to produce, and it is worth more than any of them working would
have been: it stops four implementations that could not have succeeded.

### What M11 also shows

The command is routed to whatever the Now Playing destination is — here
`com.apple.Music (54644)`, which replied
`Failing due to no content in the player and no fallback intent.` In the
originally reported bug Music was *not* running, so the same routing produced
`Destination app com.apple.Music not available` and a launch.

The routing is the mechanism. That is why the Now Playing destination idea is
now the only remaining user-space candidate — and it is public API.

Note: in this trace Music.app was already running, so it demonstrates routing,
not the launch. The launch case is the one recorded in `README.md`.

### Consequences for the per-device requirement

**The MediaRemote command carries no per-device identity.** Every Bluetooth
headset reaches `mediaremoted` through the same client — `com.apple.bluetoothd`,
pid 429 — with `SenderDevice = <Mac>`. Redmi Buds and Pixel Buds are
indistinguishable at this layer.

Per-device ON/OFF, as specified, cannot be implemented on this path.

**Worse: a Now Playing destination receives everything.** Keyboard media keys,
Control Center and AirPlay controls all route through the same mechanism. An app
that becomes the Now Playing destination absorbs those too, which is the blanket
disabling that success criteria 5, 6, 7 and 10 forbid.

Whether the destination can be scoped to only the "no other player" case —
absorbing exactly the command that would otherwise launch Music, and nothing
else — is **unmeasured**. It is the next thing to measure, not to assume.

### 2026-08-05 — M12/M13. The Now Playing sink

**M12. The app can become the Now Playing destination with public API alone,
without producing any audio.** `MPNowPlayingInfoCenter.nowPlayingInfo` plus
`playbackState = .playing`, and `MPRemoteCommandCenter` handlers, are enough.

```text
mediaremoted: activePlayerPath changed from <(null)>
              to <【 LOCL (Mac) > jp.kaizudenki.noBudsMusic (560) > default 】>
mediaremoted: nowPlayingActivePlayersIsPlayingDidChange with <Playing>
```

ADR 0003 measurement question 1: **yes**.

Note the previous value: `(null)`. Nothing held the destination, which is
exactly the condition that makes `mediaremoted` launch Music. The app is filling
a genuinely empty slot here, not displacing anyone.

**M13. The destination is released and reclaimed cleanly.**

```text
(quit)     activePlayerPath changed from <jp.kaizudenki.noBudsMusic (560)> to <(null)>
(relaunch) activePlayerPath changed from <(null)> to <jp.kaizudenki.noBudsMusic (2025)>
```

ADR 0003 measurement question 5: **yes**. Holding the destination conditionally
is mechanically possible, which is what makes risks 1 and 2 mitigable rather
than fatal. The Status toggle drives it.

**M14. Control Center displays the sink as a playing item.** `mediaremoted`
logged `NowPlayingTouchUI` requesting artwork and playback queue data for
`jp.kaizudenki.noBudsMusic`, so the fake item is being rendered. Success
criterion 10 is affected: Now Playing is not broken, but it does show this app
as playing something. Not yet confirmed visually.

**M15. The sink works. Music.app does not launch.**

With the sink holding the destination, a Pixel Buds A-Series tap:

```text
10:33:46.764  bluetoothd: Request: Command = <Play>,
              SenderBundleIdentifier = <com.apple.bluetoothd>
10:33:46.766  mediaremoted: Sending command ... command = Play
10:33:46.773  bluetoothd: Response: Command = <Play> ... returned <<private>>
              for 【 LOCL (Mac) > jp.kaizudenki.noBudsMusic (2025) > default 】
```

The command was routed to this app and answered. Neither
`Destination app com.apple.Music not available` nor `command requested a launch`
appears anywhere in the trace — the two lines that define the reported bug.

ADR 0003 measurement question 2: **yes**. Success criterion 1 is met on
Pixel Buds A-Series.

**M16. Multi-tap gestures route here too.** `Pause` (10:33:47) and `NextTrack`
(10:33:48) arrived at the sink in the same session. `NextTrack` is registered
but not absorbed — the handler returns `.noSuchContent` — and no launch followed
it, so forwarding an out-of-scope command does not reintroduce the bug.

**M17. A real player takes the destination back, and the sink yields cleanly.**

With Amazon Music playing, earbud taps controlled Amazon Music normally.

```text
activePlayerPath: noBudsMusic (7020) -> com.amazon.music (12598)
```

ADR 0003 risks 1 and 4: **cleared**. The app does not steal the destination from
a real player and does not interfere with its controls. This was the risk that
would have sunk the approach.

**M18. The claim is one-shot: once displaced, the sink never reclaims.**

After Amazon Music took the destination, `noBudsMusic` never appeared as the
active player again. The destination went on to `com.apple.Music (19944)` at
10:37:32 without passing back through the sink.

`activate()` sets `playbackState = .playing` once. Nothing re-asserts it when
the destination is released by whoever took it.

**Consequence: the protection is absent after the first real player takes over.**
If that player then quits, the destination returns to `(null)` — the condition
that causes the launch — and the app will not fill it. A working fix at launch
time becomes a non-fix after the first Spotify session.

This is the next thing to fix, and it needs care: naive periodic re-assertion
would steal the destination from a playing app and reintroduce risk 1. The
public API gives no notification of the destination becoming free
(`MRMediaRemoteGetNowPlayingApplicationPID` is private).

**Not established:** Music.app pid 19944 started at 10:37:11 during this window.
No `requested a launch` appears in the log after 10:23:09, which predates the
sink entirely — so this was most likely a manual launch, not a recurrence. Worth
confirming with the owner before treating it as either.

**M23. `IsRunningOutput` means "has an output stream", not "is playing".**
The audio gating signal does not work.

With YouTube **paused**, `com.google.Chrome.helper` reported
`runningOutput = 1` continuously for two minutes. Chrome holds its output stream
open indefinitely while paused, so the app read "something is playing" and never
claimed the destination. Music.app launched four times during that window
(`requested a launch` x4). The device-level property agrees with the per-process
one, so neither form distinguishes a paused browser tab from playback.

The deeper problem: the signal the app needs is **"does anyone hold the Now
Playing destination"**, and audio output is a poor proxy for it. Chrome held the
audio stream while *not* holding the destination — the two are decoupled, and
only the second one matters. The API that reports the holder
(`MRMediaRemoteGetNowPlayingApplicationPID`) is private.

### Where that leaves the sink

| Approach | A player is present | Nothing playing |
| --- | --- | --- |
| `.playing`, always | Steals the destination (M19) | Prevents the launch (M15) |
| `.paused`, always | Yields correctly (M20) | Music.app launches (M21) |
| `.playing`, gated on audio activity | Yields correctly | Music.app launches (M23) |

Three forms measured, none correct in both columns.

### Still unmeasured

- **Does returning `.noSuchContent` for Play fall through to the next player
  without launching Music?** If it does, the sink could hold the destination
  permanently and still let real players be controlled. `NextTrack` is already
  forwarded that way and no launch followed it — suggestive, but not the same
  command.
- **Does a keyboard media key reach the sink?** ADR 0003 risk 2. If it does,
  criterion 5 fails for as long as the destination is held.

Criterion 1 passing does not clear this. A fix that stops Music launching while
breaking the keyboard is a worse bug than the one it fixes — the stated priority
in this project's goals.

### Design questions raised by M4 and M7

Neither is decided; both need the headset connected to confirm, and both are
specification-level calls.

1. **If the earbuds' media control arrives through a `Transport=Audio` device,
   the Bluetooth-only selectability rule excludes the exact device that needs
   blocking.** `README.md` says non-Bluetooth devices cannot be selected, and
   `EventFilter` enforces it twice. That rule was written to protect keyboards
   and USB devices; a device whose transport string is `Audio` was not
   anticipated.
2. **A tier 3 identifier may not distinguish two headsets.** If both Redmi Buds
   6 Lite and Pixel Buds A-Series surface through a device reporting
   `Headset / Audio / 12 / 1` with no VID, PID or serial, they produce the *same*
   identifier and per-device rules cannot tell them apart.

### Still blocked on

- Input Monitoring must be granted before any input value can be observed.
- The two test headsets must be connected, one at a time, to answer M4 and to
  determine whether a tap produces a Consumer Control value at all — the
  question ADR 0001 is waiting on.
