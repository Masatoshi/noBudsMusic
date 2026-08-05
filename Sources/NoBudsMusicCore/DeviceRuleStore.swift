import Foundation
import os

/// Persistence for per-device rules.
///
/// Reads must be cheap and synchronous: the event path consults a rule on every
/// Play/Pause, inside a callback that runs under a system timeout.
public protocol DeviceRuleStoring: AnyObject, Sendable {
    func rule(for identifier: DeviceIdentifier) -> DeviceRule?
    func allRules() -> [DeviceRule]
    func upsert(_ rule: DeviceRule)
    func remove(_ identifier: DeviceIdentifier)
}

/// JSON-in-`UserDefaults`, held in a memory cache so the event path never hits
/// `UserDefaults` or the decoder.
public final class UserDefaultsDeviceRuleStore: DeviceRuleStoring, @unchecked Sendable {
    public static let defaultsKey = "noBudsMusic.deviceRules"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "rules")
    private let lock = NSLock()
    private var cache: [String: DeviceRule]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cache = Self.decode(from: defaults, logger: nil)
    }

    public func rule(for identifier: DeviceIdentifier) -> DeviceRule? {
        lock.withLock { cache[identifier.rawValue] }
    }

    public func allRules() -> [DeviceRule] {
        lock.withLock { Array(cache.values) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func upsert(_ rule: DeviceRule) {
        if rule.identifier.isCollisionProne && rule.blocksPlayPause {
            // Required by the brief: state the collision potential rather than
            // silently accepting a rule that may match a second identical unit.
            logger.notice(
                """
                rule saved on a collision-prone identifier \
                (tier \(rule.identifier.tier.rawValue, privacy: .public)): \
                \(rule.displayName, privacy: .public). \
                A second unit of the same model would share this rule.
                """
            )
        }
        lock.withLock { cache[rule.id] = rule }
        flush()
    }

    public func remove(_ identifier: DeviceIdentifier) {
        lock.withLock { cache[identifier.rawValue] = nil }
        flush()
    }

    private func flush() {
        let snapshot = lock.withLock { Array(cache.values) }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            logger.error("failed to persist device rules: \(error.localizedDescription)")
        }
    }

    private static func decode(from defaults: UserDefaults, logger: Logger?) -> [String: DeviceRule]
    {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        do {
            let rules = try JSONDecoder().decode([DeviceRule].self, from: data)
            return Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        } catch {
            // Losing rules is bad, but refusing to start is worse. Report and
            // continue with an empty set; nothing is blocked by default.
            logger?.error("failed to decode device rules: \(error.localizedDescription)")
            return [:]
        }
    }
}

/// Test double.
public final class InMemoryDeviceRuleStore: DeviceRuleStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: DeviceRule] = [:]

    public init(rules: [DeviceRule] = []) {
        cache = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    }

    public func rule(for identifier: DeviceIdentifier) -> DeviceRule? {
        lock.withLock { cache[identifier.rawValue] }
    }

    public func allRules() -> [DeviceRule] {
        lock.withLock { Array(cache.values) }
    }

    public func upsert(_ rule: DeviceRule) {
        lock.withLock { cache[rule.id] = rule }
    }

    public func remove(_ identifier: DeviceIdentifier) {
        lock.withLock { cache[identifier.rawValue] = nil }
    }
}
