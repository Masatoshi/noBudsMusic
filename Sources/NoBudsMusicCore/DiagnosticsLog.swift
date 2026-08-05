import Foundation
import os

/// Which layer observed an event.
///
/// The distinction is the whole Phase 3 question, so it travels with every
/// entry: the HID path can identify the device but cannot block, and the event
/// tap can block but cannot identify. An entry from `hid` with a `.block`
/// outcome means "would have been blocked", not "was blocked" — nothing on that
/// path can consume an event.
public enum ObservationPath: String, Sendable, Equatable, Codable {
    /// IOHIDManager. Identifies the device, cannot consume.
    case hid
    /// CGEventTap. Consumes, cannot identify.
    case eventTap
    /// MPRemoteCommandCenter as the Now Playing destination. Absorbs the
    /// command by receiving it and doing nothing, and knows nothing whatsoever
    /// about where it came from.
    case nowPlaying

    public var canBlock: Bool {
        self != .hid
    }
}

/// One observed media key event and the decision taken on it.
///
/// This is the primary evidence artifact. The brief requires that a failure to
/// block is explained rather than silently dropped, so the reason travels with
/// the entry.
public struct DiagnosticsEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let key: MediaKey
    /// HID usage page of the event, when it was observed on the HID path.
    public let usagePage: Int?
    /// HID usage of the event, when it was observed on the HID path.
    public let usage: Int?
    public let source: EventSource
    public let outcome: FilterOutcome
    public let path: ObservationPath

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        key: MediaKey,
        usagePage: Int? = nil,
        usage: Int? = nil,
        source: EventSource,
        outcome: FilterOutcome,
        path: ObservationPath
    ) {
        self.id = id
        self.timestamp = timestamp
        self.key = key
        self.usagePage = usagePage
        self.usage = usage
        self.source = source
        self.outcome = outcome
        self.path = path
    }

    /// True only when the event was both decided against and observed on a path
    /// that can act on the decision.
    public var wasBlocked: Bool {
        path.canBlock && outcome.isBlocked
    }

    public var summary: String {
        let usageText = [usagePage, usage]
            .map { $0.map(String.init) ?? "-" }
            .joined(separator: "/")
        return
            "[\(path.rawValue)] \(key) usage=\(usageText) source=\(source.displayName)"
            + " -> \(outcome.decision.rawValue) (\(outcome.reason.rawValue))"
    }
}

/// Bounded in-memory log plus an `os.Logger` mirror.
///
/// Bounded on purpose: this process is long-lived and a headset can emit events
/// continuously, so an unbounded array is a slow leak.
///
/// Thread-safe by lock rather than by actor isolation, because it is written
/// from the event callback, which cannot await.
public final class DiagnosticsLog: @unchecked Sendable {
    public static let defaultCapacity = 200

    private let lock = NSLock()
    private let capacity: Int
    private var storage: [DiagnosticsEntry] = []
    private var isEnabled: Bool
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "events")

    public init(capacity: Int = DiagnosticsLog.defaultCapacity, isEnabled: Bool = true) {
        self.capacity = max(1, capacity)
        self.isEnabled = isEnabled
    }

    /// Diagnostics logging can be turned off in settings. The decision itself is
    /// never affected — only whether it is recorded.
    public func setEnabled(_ enabled: Bool) {
        lock.withLock { isEnabled = enabled }
    }

    public func append(_ entry: DiagnosticsEntry) {
        let shouldRecord = lock.withLock { () -> Bool in
            guard isEnabled else { return false }
            storage.append(entry)
            if storage.count > capacity {
                storage.removeFirst(storage.count - capacity)
            }
            return true
        }
        guard shouldRecord else { return }
        // Blocked events at `.notice` so they survive into `log show` and
        // `just logs-dump`. `.debug` is only visible to a live `log stream`,
        // which meant the decisive evidence — the command that was absorbed —
        // was missing from exactly the report meant to carry it.
        if entry.outcome.isBlocked {
            logger.notice("\(entry.summary, privacy: .public)")
        } else {
            logger.debug("\(entry.summary, privacy: .public)")
        }
    }

    /// Newest first.
    public func recent(limit: Int = 50) -> [DiagnosticsEntry] {
        lock.withLock { Array(storage.suffix(limit).reversed()) }
    }

    public func clear() {
        lock.withLock { storage.removeAll(keepingCapacity: true) }
    }
}
