import Foundation
import os

/// One remote control command and the decision taken on it.
///
/// The primary evidence artifact. A command that was *not* absorbed has to be
/// explainable, so the reason travels with the entry.
public struct DiagnosticsEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let key: MediaKey
    public let outcome: FilterOutcome

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        key: MediaKey,
        outcome: FilterOutcome
    ) {
        self.id = id
        self.timestamp = timestamp
        self.key = key
        self.outcome = outcome
    }

    public var summary: String {
        "\(key.rawValue) -> \(outcome.decision.rawValue) (\(outcome.reason.rawValue))"
    }
}

/// Bounded in-memory log plus an `os.Logger` mirror.
///
/// Bounded on purpose: this process is long-lived, so an unbounded array is a
/// slow leak.
///
/// Thread-safe by lock rather than actor isolation: `MPRemoteCommandCenter`
/// handlers must answer synchronously and cannot await.
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

        // Absorbed commands at `.notice` so they survive into `log show` and
        // `just logs-dump`. `.debug` is only visible to a live `log stream`,
        // which meant the decisive evidence was missing from exactly the report
        // meant to carry it.
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
