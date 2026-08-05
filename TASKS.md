# Implementation Tasks

Status: done / todo. The measurement history is in `TECH_RESEARCH.md` (M1-M27);
the decisions are in `docs/adr/`.

## Done

- Menu bar app in AppKit, resident, no Dock icon, no windows
- Enabled toggle, menu bar visibility, launch at login, all persisted
- Occupy the Now Playing destination and forward every command (ADR 0003)
- English and Japanese localisation
- App icon, menu bar glyph and Control Center artwork from one SF Symbol
- Single instance, with three routes back when the menu bar item is hidden
- App Sandbox enabled and verified to change nothing (M26)
- Success criteria exercised on two machines, including keyboard media keys

## Abandoned, with evidence

Kept here because the reasons matter more than the outcomes.

- HID interception via IOHIDManager, CGEventTap, `kIOHIDOptionsTypeSeizeDevice`
  or DriverKit — the event never reaches any of them (M11, ADR 0001)
- Per-device blocking rules — MediaRemote carries no device identity, so this is
  impossible rather than descoped (M11, ADR 0003)
- Consuming the command with `.success` — prevents the launch but makes real
  players uncontrollable (M19)
- Declaring `.paused` — never chosen as the destination, so no protection (M21)
- Gating on audio activity — `IsRunningOutput` means "has a stream", not "is
  playing" (M23)

## Open

- done: ADR 0002 decided — open source on GitHub first, App Store revisited on
  evidence of reliability and demand. No technical constraint either way.
- Developer ID signing and notarization, if distributing directly. The app is
  currently signed with a development certificate, which is fine for machines it
  is copied to over `rsync` but not for anything downloaded.
- Developer ID signing and notarization, so the built app can be distributed to
  people who will not build from source. When that exists, both READMEs need an
  install section per channel — GitHub Releases, and Homebrew if it gets a cask.
  Until then they correctly say building is the only way.

## Not planned

- Reclaiming the destination on a schedule. The app is passive by design; a
  timer would cost the property that makes it better than the alternatives.
- A diagnostics window. `just logs` carries strictly more, and a window in this
  app cost three days of CPU spins.
