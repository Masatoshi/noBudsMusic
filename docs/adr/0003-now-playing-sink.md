# ADR 0003: Now Playing sink, and dropping per-device rules

- Status: **Proposed** — the direction is decided; viability is being measured.
- Date: 2026-08-05
- Deciders: repository owner

## Context

ADR 0001 is Rejected: a headset tap reaches `mediaremoted` as a MediaRemote
command from `bluetoothd`, with no HID device, no HID report and no
`NX_SYSDEFINED` event to intercept (`TECH_RESEARCH.md` M11).

M11 also shows *why* Music launches: `mediaremoted` routes the command to the
Now Playing destination, and when there is no destination it launches one.

## Decision

Two decisions, both made by the owner on 2026-08-05.

### 1. Per-device rules are dropped

The MediaRemote command carries no device identity — every headset arrives as
`com.apple.bluetoothd`, pid 429, `SenderDevice = <Mac>`. Redmi Buds and Pixel
Buds are indistinguishable at this layer, and no public API exposes more.

The requirement is therefore not descoped for convenience; it is **impossible on
the only surviving path**. The global Status toggle becomes the whole control
surface.

`DeviceIdentifier`, `DeviceRule`, `DeviceRuleStore` and the Devices screen stay
for now — they are the instrument that produced M11 and would still be needed if
a headset ever turns out to use HID over GATT — but they no longer gate
anything.

### 2. Become the Now Playing destination and discard the command

When Status is ON, register with `MPRemoteCommandCenter` and
`MPNowPlayingInfoCenter` so the Play command has somewhere to go, and do nothing
with it. Public API, no TCC grant, sandbox-compatible.

## Why this is not obviously safe

The mechanism has no device dimension, so it cannot distinguish *anything*. Four
risks, in descending order of how likely they are to sink the approach.

1. **Stealing the destination from a real player.** If the app holds the Now
   Playing destination unconditionally, it takes it from Spotify, a browser, or
   Music itself while they are playing. That does not merely break criterion 10
   — it breaks media control generally.
2. **Swallowing the keyboard.** Keyboard media keys route through the same
   mechanism. As the destination, the app receives and discards those too, which
   is the blanket disabling criteria 5, 6 and 7 forbid.
3. **Not becoming the destination at all.** `MPNowPlayingInfoCenter` may require
   the process to actually produce audio before macOS treats it as a player.
   Unverified.
4. **Being displaced.** Even if it works, any real player that starts will take
   the destination back — correct behaviour, but it means the fix is absent
   exactly when a player is running, which may be fine or may not.

Risks 1 and 2 are the same problem: **the app must hold the destination only
when nothing else wants it.** Whether that is expressible with public API is the
open question. `MPNowPlayingInfoCenter` reports this app's own state, not the
system's; the API that names the current Now Playing application is private
(`MRMediaRemoteGetNowPlayingApplicationPID`) and out of scope.

## Constraint: no polling

The approach's real advantage over noTunes is that it is **entirely passive**.
noTunes watches for Music.app launching and then kills it; this app registers a
destination once and is woken only when a command arrives. No timer, no
observer loop, no CPU cost at rest.

That property is not incidental — it is most of why this design is better, and
it must not be spent to solve M18. A periodic re-assertion of the Now Playing
state would reintroduce a polling loop *and* risk stealing the destination from
a playing app. Any fix for M18 has to be event-driven or it is not worth having.

## What is being measured

1. Can the app become the Now Playing destination with public API alone, without
   producing audio?
2. Does a headset tap then route to it, and does Music.app stop launching?
3. What happens to a keyboard Play/Pause while it holds the destination?
4. What happens when another app is playing — is the destination stolen?
5. Can the destination be relinquished and re-claimed, so it can be held
   conditionally?

Results go in `TECH_RESEARCH.md`. Question 5 decides whether this ADR can be
accepted: without it, risks 1 and 2 are unmitigated and the approach fails the
success criteria even if it fixes the reported bug.

## The safety property is not weakened

the project goals requires that an event whose source is `.unidentified` is never
blocked. This path never identifies a source, so routing it through the existing
`EventFilter.decide(key:source:rule:isEnabled:)` would either always pass — doing
nothing — or require gutting the rule.

Neither is acceptable. Instead the Now Playing path gets its own explicit
contract, `EventFilter.decideForNowPlaying(key:isEnabled:)`, whose inputs do not
include a source because none exists. The device-attributed rule keeps its
safety property, tests and all, and continues to govern any path that *does*
carry a source.

That makes the trade-off visible in the type signature rather than hiding it
behind a weakened rule.
