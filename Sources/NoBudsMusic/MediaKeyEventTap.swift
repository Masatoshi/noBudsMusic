import AppKit
import CoreGraphics
import Foundation
import NoBudsMusicCore
import os

/// A `CGEventTap` on the system-defined event stream (`NX_SYSDEFINED`), which is
/// where macOS delivers media keys.
///
/// **Not started in Phase 1.** The brief sequences IOHID observation (Phase 2)
/// ahead of the blocking PoC (Phase 3), and whether this tap sees a headset tap
/// at all is the open question in
/// `docs/adr/0001-event-interception-approach.md`. If the command travels
/// AVRCP -> bluetoothd -> mediaremoted, nothing reaches this tap and the answer
/// is elsewhere entirely.
///
/// Concurrency: the tap callback runs on the run loop this object was started
/// on and must decide synchronously — it cannot hop to the main actor, because
/// returning `nil` is what consumes the event and the system enforces a timeout.
/// All state read from the callback is therefore lock-guarded here rather than
/// isolated to `AppModel`.
final class MediaKeyEventTap: @unchecked Sendable {
    /// `CGEventType` has no `systemDefined` case; the raw value matches
    /// `NSEvent.EventType.systemDefined` (`NX_SYSDEFINED`, 14).
    private static let systemDefinedRawValue = UInt32(NSEvent.EventType.systemDefined.rawValue)
    /// `NSEvent.EventSubtype.screenChanged` == 8 is the subtype media keys use.
    private static let mediaKeySubtype: Int64 = 8
    /// `NX_KEYDOWN` in the packed `data1` key state field.
    private static let keyDownState: Int64 = 0x0A

    enum StartError: Error, LocalizedError {
        case accessibilityNotTrusted
        case tapCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityNotTrusted:
                "アクセシビリティ権限が許可されていません。"
            case .tapCreationFailed:
                "イベントタップを作成できませんでした。"
            }
        }
    }

    private let filter = EventFilter()
    private let sourceResolver: EventSourceResolving
    private let ruleStore: DeviceRuleStoring
    private let diagnostics: DiagnosticsLog
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "tap")

    private let lock = NSLock()
    private var isEnabled: Bool
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called after every observed event so the UI can refresh. Invoked off the
    /// main thread; hop yourself.
    var onEvent: (@Sendable (DiagnosticsEntry) -> Void)?

    init(
        sourceResolver: EventSourceResolving = UnidentifiedSourceResolver(),
        ruleStore: DeviceRuleStoring,
        diagnostics: DiagnosticsLog,
        isEnabled: Bool
    ) {
        self.sourceResolver = sourceResolver
        self.ruleStore = ruleStore
        self.diagnostics = diagnostics
        self.isEnabled = isEnabled
    }

    var isRunning: Bool {
        lock.withLock { tap != nil }
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { isEnabled = enabled }
    }

    // MARK: - Lifecycle

    /// Installs the tap on the current thread's run loop.
    func start() throws {
        guard !isRunning else { return }
        guard Permissions.accessibility == .granted else {
            throw StartError.accessibilityNotTrusted
        }

        let mask = CGEventMask(1 << Self.systemDefinedRawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                // `.defaultTap` (not `.listenOnly`) is required to be able to
                // drop an event. The filter still passes unless a rule matches.
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { proxy, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let tap = Unmanaged<MediaKeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
                    return tap.handle(proxy: proxy, type: type, event: event)
                },
                userInfo: context
            )
        else {
            throw StartError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.withLock {
            self.tap = tap
            self.runLoopSource = source
        }
        logger.info("event tap started")
    }

    func stop() {
        let (tap, source) = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            defer {
                self.tap = nil
                self.runLoopSource = nil
            }
            return (self.tap, self.runLoopSource)
        }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        logger.info("event tap stopped")
    }

    // MARK: - Callback

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // The system disables a tap that is too slow or that errors. Re-enable
        // rather than silently going deaf.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.error("tap disabled by system (\(type.rawValue)); re-enabling")
            if let tap = lock.withLock({ self.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.systemDefinedRawValue else {
            return Unmanaged.passUnretained(event)
        }
        guard let key = Self.mediaKey(from: event) else {
            return Unmanaged.passUnretained(event)
        }

        let query = EventSourceQuery(
            sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceStateID: event.getIntegerValueField(.eventSourceStateID),
            timestamp: event.timestamp
        )
        let source = sourceResolver.source(for: query)
        let rule = source.identifier.flatMap { ruleStore.rule(for: $0) }
        let enabled = lock.withLock { isEnabled }
        let outcome = filter.decide(key: key, source: source, rule: rule, isEnabled: enabled)

        let entry = DiagnosticsEntry(
            key: key,
            source: source,
            outcome: outcome,
            // This path can consume. See `ObservationPath`.
            path: .eventTap
        )
        diagnostics.append(entry)
        onEvent?(entry)

        return outcome.isBlocked ? nil : Unmanaged.passUnretained(event)
    }

    /// Unpacks the media key from a system-defined event.
    ///
    /// `CGEvent` has no accessor for the system-defined `subtype` / `data1`
    /// fields, so this bridges to `NSEvent`, which does. `data1` packs the key
    /// code in the high 16 bits and the key state in bits 8-15. Only key-down is
    /// acted on; ignoring key-up avoids counting one physical tap twice.
    private static func mediaKey(from event: CGEvent) -> MediaKey? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        guard nsEvent.type == .systemDefined else { return nil }
        guard nsEvent.subtype.rawValue == UInt16(mediaKeySubtype) else { return nil }

        let data1 = Int64(nsEvent.data1)
        let keyCode = Int32(truncatingIfNeeded: (data1 & 0xFFFF_0000) >> 16)
        let keyState = (data1 & 0x0000_FF00) >> 8
        guard keyState == keyDownState else { return nil }

        return MediaKey.from(rawKeyCode: keyCode)
    }
}
