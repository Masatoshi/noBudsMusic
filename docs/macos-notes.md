# macOS notes

Things that cost real time to find while building this app, on macOS 26 with
Xcode 26 and Swift 6. Each one is stated with the evidence that established it,
because most of them contradict a reasonable first guess.

`TECH_RESEARCH.md` has the full measurement log; this file is the part that
generalises beyond this project.

## MediaRemote and the Now Playing destination

### A Bluetooth headset tap never touches HID

Tapping a Bluetooth headset does not produce a HID device, a HID report, or an
`NX_SYSDEFINED` event. `bluetoothd` issues a MediaRemote command directly:

```text
bluetoothd: (MediaRemote) Request: Command = <Play>,
            SenderBundleIdentifier = <com.apple.bluetoothd>
mediaremoted: Received command from client
            <bundleIdentifier = com.apple.bluetoothd>: command = Play
```

Measured with Pixel Buds A-Series: the IOHID device inventory is byte-identical
with the headset connected and disconnected — 12 devices, same names, same
properties. Nothing appears on connect.

This eliminates `IOHIDManager`, `CGEventTap`, `kIOHIDOptionsTypeSeizeDevice` and
DriverKit for anything that wants to see or block such a tap. They all sit on a
path the event never takes.

Some headsets use HID over GATT and would behave differently. Measure the device
in front of you rather than assuming either way.

### The command carries no device identity

Every Bluetooth headset reaches `mediaremoted` as `com.apple.bluetoothd`, with
`SenderDevice = <Mac>`. Two different headsets are indistinguishable, and so is
a keyboard media key. Per-device behaviour is not possible on this path with
public API. `MRMediaRemoteGetNowPlayingApplicationPID` is private.

### macOS launches a player when there is no Now Playing destination

That is the whole mechanism behind Music.app opening by itself:

```text
mediaremoted: Destination app com.apple.Music not available for command
              <command = Play>, and command requested a launch.
```

Registering as that destination removes the reason to launch.

### `.playing` versus `.paused`, and `.success` versus `.noSuchContent`

Four combinations, and only one is correct. Measured:

| `MPNowPlayingInfoCenter.playbackState` | Command handler returns | Result |
| --- | --- | --- |
| `.playing` | `.success` | No launch, but real players lose control of their own playback |
| `.playing` | `.noSuchContent` | **No launch, and real players keep control** |
| `.paused` | either | Never chosen as the destination, so no effect at all |

`.paused` is never selected as the active player even when the alternative is
nobody. `.success` consumes the command, so a browser playing a video can no
longer be paused from the headset. `.noSuchContent` asks the system to look
elsewhere: it passes the command to the real player when there is one, and does
not request a launch when there is not.

An app can hold the destination without producing any audio.
`MPNowPlayingInfoCenter.nowPlayingInfo` plus `playbackState` is enough.

### Appearing in Control Center is unavoidable

While an app holds the destination, Control Center lists it. Omitting
`MPMediaItemPropertyTitle` does not hide the entry — the display falls back to
the app name. The only choice is what the line says.

### `MPMediaItemArtwork`'s request handler runs off the main thread

It is invoked on MediaPlayer's own `accessQueue`, synchronously, while
`nowPlayingInfo` is being converted. A handler written inline inside a
`@MainActor` type inherits that isolation and traps:

```text
EXC_BREAKPOINT / SIGTRAP on */accessQueue
  swift_task_checkIsolatedSwift
  closure #1 in ...artwork()
  -[MPMediaItemArtwork jpegDataWithSize:]
```

Render the image eagerly and have the handler only return it. AppKit drawing
inside the handler would be unsafe even without the isolation trap.

### `IsRunningOutput` means "has an output stream", not "is playing"

`kAudioProcessPropertyIsRunningOutput`, and the device-level
`kAudioDevicePropertyDeviceIsRunningSomewhere`, both report a browser with a
*paused* tab as running output. Chrome held it continuously for two minutes with
YouTube paused. Neither is a usable "is anything playing" signal.

The per-process form is still worth using where you need one, because it names
the process:

```text
audio process objects: 47
  pid=66257 bundle=com.google.Chrome.helper runningOutput=1
```

## IOKit HID

### Enumeration works without Input Monitoring; input does not

`IOHIDManagerCopyDevices` returns the full device list with the grant denied.
Only `IOHIDManagerOpen` fails, with `kIOReturnNotPermitted` (`-536870174`).

So a populated device list next to an empty event log means the permission is
missing — not that the device produced nothing. Check the permission before
concluding anything about the hardware.

### `IOHIDManagerOpen` is all-or-nothing

Matching every device and opening the manager fails with
`kIOReturnExclusiveAccess` (`-536870203`) if *any* single matched device is held
exclusively by another process. Karabiner-Elements seizing keyboards is enough
to fail the whole manager.

Open devices individually with `IOHIDDeviceOpen` instead. You keep the devices
that are available, and you learn which ones are not.

### `CGEventType` has no `systemDefined` case

`NSEvent.EventType.systemDefined` (raw value 14, `NX_SYSDEFINED`) exists;
`CGEventType` has no matching case. Build the tap mask from the raw value and
compare `type.rawValue`.

`CGEvent` also exposes no `subtype` or `data1` accessor, so unpacking a media key
means bridging through `NSEvent(cgEvent:)`.

## SwiftUI on macOS

### Reading `@Observable` state in a `Scene` body pins the main thread

The stack loops forever:

```text
AppGraph.graphDidChange -> AppDelegate.scenesDidChange -> makeMainMenu ->
AppKitMainMenuItem.updateMainMenu -> invalidateProperties -> updateViewGraph
```

100% of one core, and nothing else on the main thread runs again — no timers, no
dispatched blocks, no further delegate callbacks, no Apple Events. The app looks
alive because the menu bar item was installed before the loop started.

`sample <pid>` is the fastest way to see it. `ps -o %cpu` after any UI change is
cheaper still.

### `MenuBarExtra(isInserted:)` writes back on every scene update

If that write reaches `UserDefaults` — directly through `@AppStorage`, or through
a setter that persists unconditionally — the store notifies the scene, the scene
re-evaluates, and it writes again. Same loop, same 100%.

Guard the setter so an unchanged value never touches storage.

### The same loop reappears from the `MenuBarExtra` content

SwiftUI builds the app's main menu from that content, so reading `@Observable`
state there re-enters the loop even after the `Scene` body is clean.

Three separate triggers were found and closed one at a time before the mechanism
itself was addressed. For a menu bar app of a few items, `NSStatusItem` plus
`NSMenu` has no scene graph and no main-menu reconstruction, and the whole class
of bug disappears. Rebuilding the menu from your model in `menuNeedsUpdate` is
the entire state-propagation story.

### `application(_:open:)` is not delivered under the SwiftUI App lifecycle

With `@NSApplicationDelegateAdaptor`, `applicationShouldHandleReopen` **is**
delivered but `application(_:open:)` is **not**. SwiftUI consumes the `GURL`
Apple Event and routes it to `onOpenURL` on a live `View` — and a `MenuBarExtra`
app has no live view while the menu is closed.

The log shows the event arriving at the process while neither method runs.
Registering an `NSAppleEventManager` handler for `kInternetEventClass` /
`kAEGetURL` works, but only if it is registered *after* SwiftUI installs its own;
inside `applicationDidFinishLaunching` is too early and a
`DispatchQueue.main.async` hop is enough.

### `SwiftUI.Settings` shadows a bare `Settings` type

`SwiftUI` exports a `Settings` scene, so your own `Settings` type is ambiguous in
any file importing both. Name it something else.

### An `NSHostingController` in a `MenuBarExtra`-only app can pin the main thread

Same loop as above. `sceneBridgingOptions = []` does not help. An `NSHostingView`
inside a plain `NSViewController` behaved better, but the reliable fix was to
stop hosting SwiftUI in that app at all.

## Code signing, TCC and the sandbox

### TCC grants are keyed to the signing identity

An ad-hoc signature changes whenever the binary changes, so every rebuild is a
new client and starts with Accessibility and Input Monitoring denied. Neither API
raises: `CGEvent.tapCreate` returns `nil`, `IOHIDManagerOpen` returns
`kIOReturnNotPermitted`.

Sign development builds with a real certificate and the grants persist. Passing
`CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` to `xcodebuild` is enough; use the
certificate's SHA-1 rather than "Apple Development", which resolves to a "Mac
Development" certificate that may not exist.

### `kAXTrustedCheckOptionPrompt` is unusable under strict concurrency

It is imported as a mutable, non-`Sendable` global. The literal it holds,
`"AXTrustedCheckOptionPrompt"`, is stable API — spell it out.

### A sandboxed app can still hold the Now Playing destination

Verified from inside a container: `MPNowPlayingInfoCenter` still wins the
destination, `SMAppService` registers a login item, and a custom URL scheme still
reaches the running instance.

`DistributedNotificationCenter` is the exception — a sandboxed app can only post
under an app-group-prefixed name. If you only need to poke your own running
instance, opening your own URL scheme through `NSWorkspace` avoids provisioning
an app group for one message.

The sandbox relocates `UserDefaults` into the container, so settings start from
defaults.

### Gatekeeper only intervenes on quarantined files

An app signed with a *development* certificate is rejected by
`spctl -a -t exec`, but still launches on another Mac if it arrives without the
`com.apple.quarantine` attribute. `rsync` and `scp` do not set it; downloading
and AirDrop do.

That makes `rsync` a workable way to move a build between your own machines, and
not a substitute for Developer ID plus notarization for anything else.

Homebrew Cask applies quarantine to downloaded files. A cask whose checksum
matches and whose download succeeds still produces an app that will not open:
`open` returns 0 and no process appears. Measured against the real release
artifact, not a simulation. Homebrew is not the obstacle — the signature is.

`brew install --cask --no-quarantine` used to be the escape hatch. It was
removed; on Homebrew 6.0.15 it is `Error: invalid option: --no-quarantine`.
Notarization is the only route left that does not involve telling users to strip
an attribute by hand.

## Build setup

### A framework target can fail ad-hoc signing

`CodeSign .../Foo.framework/Versions/A` failing with `bundle format
unrecognized, invalid, or unsuitable` went away by making the module a static
library instead. For a module that only needs to be linked into one app, there is
nothing a framework buys.

### An XcodeGen test bundle needs `GENERATE_INFOPLIST_FILE`

Otherwise `xcodebuild` refuses to sign it: *Cannot code sign because the target
does not have an Info.plist file.*

### LaunchServices can bind a URL scheme to a stale build

Every built copy registers the scheme, and LaunchServices resolves it to whichever
copy it recorded last — which may be an old DerivedData path. If a URL opens the
wrong copy, check `lsregister -dump` before suspecting the code.
