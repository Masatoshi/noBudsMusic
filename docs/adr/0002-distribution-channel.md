# ADR 0002: Distribution channel

- Status: **Accepted** — the sequencing is decided. The channel itself is
  deliberately deferred.
- Date: 2026-08-05
- Deciders: repository owner

## Context

Mac App Store distribution was raised as an intent on 2026-08-05. It conflicts
with the planned mechanism:

- **The store requires the App Sandbox.** Not negotiable.
- **The planned mechanisms require TCC grants.** `CGEventTap` with `.defaultTap`
  needs Accessibility; `IOHIDManager` input needs Input Monitoring. Whether
  either survives the sandbox is unverified.

The deeper problem is that this is not the binding constraint yet. Whether the
app can block the event *at all* is still unmeasured — the AVRCP hypothesis in
`TECH_RESEARCH.md` has it possibly not reaching any interceptable layer. Picking
a distribution channel for a mechanism that may not exist would constrain the
implementation for nothing.

## Decision

**Build first, choose the channel afterwards.**

1. Implement and measure without regard to the sandbox. Phases 2-4 proceed as
   written; the App Sandbox stays off.
2. Once the app actually works, evaluate whether the chosen mechanism survives
   the sandbox, and decide the channel then.
3. **If the store turns out to be incompatible, publish as open source on
   GitHub** and distribute directly. This is the named fallback, not a
   consolation — it removes the App Review risk entirely and costs only the
   store's discovery and update plumbing.

This is a deliberate ordering decision, not a deferral by neglect: it keeps the
implementation unconstrained while the hard question (does blocking work at all)
is still open, and it means no design compromise is made for a channel that may
never be used.

## What this decision explicitly does not require

The implementation carries **no sandbox constraints**. Do not contort the code
to keep the store option open — no avoiding APIs, no restructuring, no defensive
architecture for a decision that has not been made.

The one thing worth knowing, because it is free: the current code happens not to
do anything sandbox-hostile (no writes outside the container, no absolute paths
outside the bundle, no shelling out). That is worth not throwing away casually,
but it is not a rule and not a review item.

## Inputs for the later decision

Recorded now so the evaluation does not start from scratch.

| Mechanism | Store viability |
| --- | --- |
| `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter` (Now Playing routing) | Best. Public API, no TCC grant, sandbox-friendly |
| `CGEventTap` + `IOHIDManager` | Unverified — needs the measurement below |
| IOHID seize | Effectively out |
| DriverKit | Out |

Not blockers, confirmed: `SMAppService` (launch at login) works sandboxed, and
`LSUIElement` menu bar apps are acceptable on the store.

Unverified, to be measured after the implementation works:

1. Can a sandboxed build be granted Accessibility?
2. Can a sandboxed build be granted Input Monitoring?
3. Can it then create a *consuming* (`.defaultTap`) event tap, not just a
   listen-only one?
4. Would App Review accept an app whose function is intercepting system-wide
   media input? This one cannot be measured locally at all — it is a submission
   outcome.

The measurement for 1-3 is mechanical: enable `com.apple.security.app-sandbox`,
rebuild, re-run the same manual matrix that the unsandboxed build passed, and
record both results in `TECH_RESEARCH.md`.

## Consequences

- Phase 2-4 are unaffected. No implementation work changes because of this ADR.
- The bundle identifier `jp.kaizudenki.noBudsMusic` is fixed either way, and is
  what App Store Connect would register if it comes to that.
- The MIT license already suits the GitHub fallback; no change needed.
- If the repository does become public, its documentation and commit messages
  should be in English. `README.md` is currently Japanese. That is a task for
  the publication decision, not now.
- Revisit this ADR after Phase 4, when there is something to distribute.
