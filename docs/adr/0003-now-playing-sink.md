# ADR 0003: Now Playing sink, and dropping per-device rules

- Status: **Accepted** — measured working end to end (M24).
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

`DeviceIdentifier`, `DeviceRule`, `DeviceRuleStore`, the Devices screen,
`HIDDeviceMonitor` and `MediaKeyEventTap` have been deleted. They controlled
nothing once this decision was made, and keeping ~1,400 lines of inert code to
hedge against a headset that might use HID over GATT is the speculative
future-proofing this project rules out. They remain in the first commit if the
measurement ever needs reproducing.

Removing them also removed every TCC dependency: the app now needs neither
Accessibility nor Input Monitoring. That materially improves ADR 0002's inputs,
which is noted there rather than reopened here.

### 2. Occupy the Now Playing destination, and forward everything

When enabled, register with `MPRemoteCommandCenter` and
`MPNowPlayingInfoCenter` so the Play command has somewhere to go — then answer
**`.noSuchContent`**, never `.success`.

That single return value is the whole design, and it took four measured failures
to find:

- `.success` prevents the launch but consumes the command, so real players
  become uncontrollable (M19).
- `.noSuchContent` also prevents the launch, and `mediaremoted` passes the
  command on to whatever is actually playing (M24).

**The app therefore blocks nothing.** It registers itself as the destination,
because the absence of one is what makes macOS launch a player. Everything that
arrives is passed straight through.

Public API, no TCC grant, sandbox-compatible, and passive — no timer, no
observer loop, nothing running at rest.

## Why this is not obviously safe

The mechanism has no device dimension, so it cannot distinguish *anything*. Four
risks, in descending order of how likely they are to sink the approach.

1. **Stealing the destination from a real player.** If the app holds the Now
   Playing destination unconditionally, it takes it from Spotify, a browser, or
   Music itself while they are playing. That does not merely break criterion 10
   — it breaks media control generally.
2. **Swallowing the keyboard.** Keyboard media keys route through the same
   mechanism. As the destination, the app receives and discards those too, which
   is the blanket disabling criteria 5, 6 and 7 forbid. Cleared by
   `.noSuchContent`: the command is forwarded rather than consumed. Verified on
   hardware — keyboard Play/Pause and volume keys both behave normally on
   MacBookPro18,4, macOS 26.5.2 (25F84).
3. ~~**Not becoming the destination at all.**~~ Cleared by M12: public API alone
   is enough, without producing audio.
4. **Being displaced, and not coming back.** Cleared as a correctness concern by
   M17 — a real player does take the destination and this app yields, which is
   what should happen. But M18 shows the app never reclaims it afterwards, so
   the protection is absent from then on.

**Resolved by `.noSuchContent`.** Risk 1 was wrongly cleared by M17, confirmed by
M19, Amazon Music
took the destination back, but Chrome did not: with `playbackState = .playing`
this app stole the destination mid-YouTube and swallowed its Play/Pause. M17
generalised from one player.

`playbackState = .paused` (M20) makes the app yield to anything actually
playing, but M21 showed it is then never chosen as the destination at all — so
it does not prevent the launch either. Neither fixed state works.

**The resolution is to make the state conditional.** The app declares
`.playing`, but only holds the destination while nothing else is playing audio,
and releases it the moment something starts. `AudioActivityMonitor` supplies
that signal from CoreAudio's per-process audio objects
(`kAudioProcessPropertyIsRunningOutput`), event-driven, no polling.

This works because the bug can only occur during silence: `mediaremoted`
launches Music precisely when no player holds the destination. Holding it only
during silence covers exactly the failing case and nothing else.

The remaining shape of the problem: **the app must hold the destination only
when nothing else wants it**, and must notice when that becomes true again
without polling. Whether that is expressible with public API is the open
question. `MPNowPlayingInfoCenter` reports this app's own state, not the
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

## What was measured

1. Can the app become the destination with public API alone, without producing
   audio? **Yes** (M12).
2. Does a headset tap route to it, and does Music.app stop launching?
   **Yes** (M15).
3. What happens to other players while it holds the destination? With
   `.success`, they lose control (M19). With `.noSuchContent`, they keep it
   (M24).
4. Is the destination stolen from a playing app? Not with `.noSuchContent` —
   real players take it back as soon as they play (M24).
5. Can the destination be released and reclaimed? **Yes** (M13).

Three intermediate designs were measured and discarded: `.paused` (never chosen
as the destination, M21), audio-activity gating (`IsRunningOutput` means "has a
stream", not "is playing", M23), and `.success` (M19).

Results are in `TECH_RESEARCH.md`. Answered so far: 1 yes (M12), 2 yes (M15),
4 no — the destination is not stolen from a playing app (M17), 5 yes (M13).

**Question 3 is unanswered and decides whether this ADR can be accepted.** If a
keyboard media key is swallowed, the app breaks criterion 3 for as long as it is
on, which outranks the bug it fixes.

## The old safety property is gone

This project used to require that an event whose source is `.unidentified`
is never blocked. That rule protected keyboards and was enforceable because the
HID path carried a device identity.

It was not relaxed — the path it governed was deleted. Commands now arrive with
no source at all, so there is nothing for such a rule to test.

What replaces it is weaker, and it is now stated plainly: the app
absorbs Play/Pause whenever Status is ON, and the only control over what it
absorbs is *when* it holds the destination. Recording that honestly matters more
than preserving the appearance of a safety property that no longer has anything
to stand on.
