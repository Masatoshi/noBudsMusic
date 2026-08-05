import Foundation

public enum PermissionState: String, Sendable, Equatable {
    case granted
    case denied
    /// Not yet requested, or the system will not say.
    case undetermined
}

/// The permissions this app may need, depending on which interception path
/// Phase 2 and 3 settle on.
///
/// Both are surfaced in Diagnostics whether or not they are currently required:
/// the brief forbids failing silently when a permission is missing, and a
/// missing grant is the most common reason for observing nothing at all.
public struct PermissionStatus: Sendable, Equatable {
    /// Needed by IOHIDManager to receive input values.
    public let inputMonitoring: PermissionState
    /// Needed by CGEventTap to create a tap that can consume events.
    public let accessibility: PermissionState

    public init(inputMonitoring: PermissionState, accessibility: PermissionState) {
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
    }

    public static let unknown = PermissionStatus(
        inputMonitoring: .undetermined,
        accessibility: .undetermined
    )

    public var allGranted: Bool {
        inputMonitoring == .granted && accessibility == .granted
    }
}
