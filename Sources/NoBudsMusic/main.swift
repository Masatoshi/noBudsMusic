import AppKit

// An AppKit entry point rather than a SwiftUI `App`.
//
// The SwiftUI `MenuBarExtra` version pinned the main thread at 100% CPU three
// separate times, always in the same loop: `scenesDidChange -> makeMainMenu ->
// invalidateProperties -> updateViewGraph`. Each fix closed one trigger and left
// the mechanism intact. `NSStatusItem` has no scene graph and no main-menu
// reconstruction, so the whole class of bug is gone rather than avoided.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
