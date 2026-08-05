import AppKit
import ApplicationServices
import Foundation
import IOKit.hid
import NoBudsMusicCore

/// Permission checks and the links that let the user fix them.
///
/// Both grants fail quietly at the API level — `IOHIDManagerOpen` succeeds but
/// delivers no values, and `CGEvent.tapCreate` returns `nil` — so the app has to
/// ask explicitly and show the result rather than inferring "no events" from
/// silence.
enum Permissions {
    // MARK: - Input Monitoring (IOHIDManager)

    static var inputMonitoring: PermissionState {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .undetermined
        }
    }

    /// Shows the system prompt. Returns `true` only if already granted; the
    /// first call returns `false` while the prompt is still on screen.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - Accessibility (CGEventTap)

    static var accessibility: PermissionState {
        AXIsProcessTrusted() ? .granted : .undetermined
    }

    /// Shows the system prompt if trust has not been granted yet.
    @discardableResult
    static func requestAccessibility() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is imported as a mutable, non-Sendable
        // global and cannot be referenced under strict concurrency. The literal
        // it holds is stable API, so it is spelled out here instead.
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Status

    static var status: PermissionStatus {
        PermissionStatus(inputMonitoring: inputMonitoring, accessibility: accessibility)
    }

    // MARK: - Settings links

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
