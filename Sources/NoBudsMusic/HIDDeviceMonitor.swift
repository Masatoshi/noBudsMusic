import Foundation
import IOKit.hid
import NoBudsMusicCore
import os

/// IOHIDManager: enumerates HID devices and observes Consumer Control input.
///
/// This is the Phase 2 instrument. It answers the question ADR 0001 is blocked
/// on — **does a Bluetooth headset tap appear on the HID path at all?** — and it
/// is the only layer that can say *which* device produced an input.
///
/// It cannot block anything. Entries it records carry `ObservationPath.hid`, so
/// a `.block` outcome from here means "would have been blocked", never "was".
///
/// Concurrency: the manager is scheduled on the main run loop, so its callbacks
/// arrive on the main thread — but the C callback boundary erases that, so state
/// is lock-guarded rather than actor-isolated, matching `MediaKeyEventTap`.
final class HIDDeviceMonitor: HIDDeviceEnumerating, @unchecked Sendable {
    enum StartError: Error, LocalizedError {
        case inputMonitoringDenied
        case exclusiveAccess
        case openFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .inputMonitoringDenied:
                "入力監視（Input Monitoring）が許可されていません。"
            case .exclusiveAccess:
                "他のプロセスがHIDデバイスを排他的に使用しているため開けませんでした。"
            case .openFailed(let code):
                "HIDマネージャを開けませんでした（\(IOReturnName.describe(code))）。"
            }
        }
    }

    /// The two codes this app actually hits, spelled out. A bare
    /// `IOReturn=-536870203` in a log is unreadable, and the difference between
    /// these two is the difference between "grant the permission" and "another
    /// process owns the device".
    enum IOReturnName {
        static let notPermitted: IOReturn = -536_870_174  // 0xE00002E2
        static let exclusiveAccess: IOReturn = -536_870_203  // 0xE00002C5

        static func describe(_ code: IOReturn) -> String {
            switch code {
            case notPermitted: "kIOReturnNotPermitted (\(code))"
            case exclusiveAccess: "kIOReturnExclusiveAccess (\(code))"
            default: "IOReturn \(code)"
            }
        }
    }

    private let filter = EventFilter()
    private let ruleStore: DeviceRuleStoring
    private let diagnostics: DiagnosticsLog
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "hid")

    private let lock = NSLock()

    /// Two managers, because opening and enumerating want opposite matching.
    ///
    /// Measured: a single manager matching every device fails
    /// `IOHIDManagerOpen` with `kIOReturnExclusiveAccess` even with Input
    /// Monitoring granted — something else on this machine holds a device
    /// exclusively (Karabiner-Elements seizes keyboards, and its DriverKit
    /// virtual devices are present). Opening only what needs observing avoids
    /// the contested devices entirely.
    ///
    /// The inventory manager is never opened; `IOHIDManagerCopyDevices` works
    /// without it, which is how the Devices screen still lists everything.
    private let inventoryManager: IOHIDManager
    private let observerManager: IOHIDManager
    private var isRunning = false
    private var isEnabled: Bool
    /// Retained so they stay open and scheduled.
    private var openedDevices: [IOHIDDevice] = []

    /// Called after every observed input and on every device connect/disconnect.
    /// Invoked on the run loop thread; hop yourself.
    var onEvent: (@Sendable (DiagnosticsEntry) -> Void)?
    var onDeviceSetChanged: (@Sendable () -> Void)?

    init(ruleStore: DeviceRuleStoring, diagnostics: DiagnosticsLog, isEnabled: Bool) {
        self.ruleStore = ruleStore
        self.diagnostics = diagnostics
        self.isEnabled = isEnabled
        self.inventoryManager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        self.observerManager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        // Everything, for the Devices screen. Never opened.
        IOHIDManagerSetDeviceMatching(inventoryManager, nil)
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { isEnabled = enabled }
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !lock.withLock({ isRunning }) else { return }

        // Device arrival / removal notifications. Scheduled but never opened —
        // opening is done per device below.
        IOHIDManagerSetDeviceMatching(
            observerManager,
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer] as CFDictionary
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            observerManager, Self.deviceChangedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            observerManager, Self.deviceChangedCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            observerManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        lock.withLock { isRunning = true }
        let opened = openObservableDevices()

        // Per-device open rather than `IOHIDManagerOpen`, which is all-or-
        // nothing: measured, it fails the whole manager with
        // `kIOReturnExclusiveAccess` when any single matched device is held by
        // another process. Opening individually keeps the devices that are
        // available and, more importantly, names the ones that are not — which
        // is itself a Phase 3 input, since seize viability depends on who else
        // is holding what.
        guard opened > 0 else {
            let permission = Permissions.inputMonitoring
            if permission != .granted {
                throw StartError.inputMonitoringDenied
            }
            throw StartError.exclusiveAccess
        }
    }

    /// Opens every Consumer-page device that will open, and reports each result.
    /// Returns the number now being observed.
    @discardableResult
    func openObservableDevices() -> Int {
        let already = lock.withLock { openedDevices }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var opened: [IOHIDDevice] = []
        var refused: [String] = []

        for device in consumerDevices() where !already.contains(device) {
            let info = Self.info(for: device)
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                refused.append("\(info.displayName) [\(IOReturnName.describe(result))]")
                continue
            }
            // Consumer page only, again at the device level: without it this
            // would receive every key the device reports.
            IOHIDDeviceSetInputValueMatching(
                device,
                [kIOHIDElementUsagePageKey: kHIDPage_Consumer] as CFDictionary
            )
            IOHIDDeviceRegisterInputValueCallback(device, Self.inputValueCallback, context)
            IOHIDDeviceScheduleWithRunLoop(
                device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            opened.append(device)
            logger.notice(
                """
                observing \(info.displayName, privacy: .public) \
                transport=\(info.transport.label, privacy: .public)
                """
            )
        }

        for name in refused {
            logger.error("cannot open \(name, privacy: .public)")
        }

        let total = lock.withLock { () -> Int in
            openedDevices.append(contentsOf: opened)
            return openedDevices.count
        }
        // Only when something changed. The arrival callback fires once per
        // matched device, and an unconditional line here buries the actual
        // measurement under repeats.
        if !opened.isEmpty || !refused.isEmpty {
            logger.notice(
                """
                hid monitor observing \(total, privacy: .public) device(s), \
                \(refused.count, privacy: .public) refused
                """
            )
        }
        return total
    }

    /// Devices whose primary usage page is Consumer (0x0C) — the media control
    /// interfaces. Read from the never-opened inventory manager.
    private func consumerDevices() -> [IOHIDDevice] {
        guard let all = IOHIDManagerCopyDevices(inventoryManager) as? Set<IOHIDDevice> else {
            return []
        }
        return all.filter { Self.int($0, kIOHIDPrimaryUsagePageKey) == Int(kHIDPage_Consumer) }
    }

    func stop() {
        guard lock.withLock({ isRunning }) else { return }
        let devices = lock.withLock { () -> [IOHIDDevice] in
            defer { openedDevices.removeAll() }
            return openedDevices
        }
        for device in devices {
            IOHIDDeviceUnscheduleFromRunLoop(
                device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerUnscheduleFromRunLoop(
            observerManager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        lock.withLock { isRunning = false }
        logger.info("hid monitor stopped")
    }

    // MARK: - Enumeration

    func connectedDevices() -> [HIDDeviceInfo] {
        guard let devices = IOHIDManagerCopyDevices(inventoryManager) as? Set<IOHIDDevice> else {
            return []
        }
        return devices.map(Self.info(for:))
    }

    /// Writes the full inventory to the log.
    ///
    /// A Phase 2 deliverable in its own right: what IOHID actually reports for
    /// each device — and which properties it omits — is the raw material for the
    /// identifier-tier decision and for judging whether a headset is visible
    /// here at all.
    func logInventory() {
        let devices = connectedDevices()
        logger.notice("hid inventory: \(devices.count, privacy: .public) device(s)")
        for info in devices {
            let id = DeviceIdentifier.make(from: info)
            logger.notice(
                """
                  \(info.displayName, privacy: .public) \
                transport=\(info.transport.label, privacy: .public) \
                vid=\(info.vendorID.map { String(format: "0x%04X", $0) } ?? "-", privacy: .public) \
                pid=\(info.productID.map { String(format: "0x%04X", $0) } ?? "-", privacy: .public) \
                serial=\(info.serialNumber == nil ? "none" : "present", privacy: .public) \
                usage=\(info.primaryUsagePage.map(String.init) ?? "-", privacy: .public)\
                /\(info.primaryUsage.map(String.init) ?? "-", privacy: .public) \
                tier=\(id.tier.rawValue, privacy: .public)
                """
            )
        }
    }

    /// Reads every property the brief asks for. All are optional because IOHID
    /// populates them inconsistently — a consumer earbud with no serial number
    /// is the normal case, not an error.
    static func info(for device: IOHIDDevice) -> HIDDeviceInfo {
        HIDDeviceInfo(
            transport: DeviceTransport.from(raw: string(device, kIOHIDTransportKey)),
            productName: string(device, kIOHIDProductKey),
            manufacturer: string(device, kIOHIDManufacturerKey),
            vendorID: int(device, kIOHIDVendorIDKey),
            productID: int(device, kIOHIDProductIDKey),
            serialNumber: string(device, kIOHIDSerialNumberKey),
            locationID: int(device, kIOHIDLocationIDKey),
            primaryUsagePage: int(device, kIOHIDPrimaryUsagePageKey),
            primaryUsage: int(device, kIOHIDPrimaryUsageKey)
        )
    }

    private static func string(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    static func int(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }

    // MARK: - Callbacks

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().handle(value: value)
    }

    private static let deviceChangedCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        // A headset that connects after launch has to be picked up, not just
        // listed. This is the path a paired earbud takes.
        monitor.openObservableDevices()
        monitor.onDeviceSetChanged?()
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))

        // Key-up carries 0. Ignoring it keeps one physical tap from being
        // counted twice.
        guard IOHIDValueGetIntegerValue(value) != 0 else { return }

        guard let key = MediaKey.from(consumerUsage: usage) else {
            // Deliberately logged: the Phase 2 question includes "what *does*
            // arrive", and an unmodelled usage from a headset is a finding.
            logger.debug("unmodelled consumer usage \(usage, privacy: .public)")
            return
        }

        // Unlike `CGEvent`, a HID value knows exactly which device produced it.
        // That is the whole reason this layer exists.
        let info = Self.info(for: IOHIDElementGetDevice(element))
        let source = EventSource.device(DeviceIdentifier.make(from: info), info: info)

        let rule = source.identifier.flatMap { ruleStore.rule(for: $0) }
        let enabled = lock.withLock { isEnabled }
        let outcome = filter.decide(key: key, source: source, rule: rule, isEnabled: enabled)

        let entry = DiagnosticsEntry(
            key: key,
            usagePage: usagePage,
            usage: usage,
            source: source,
            outcome: outcome,
            // This path observes; it cannot consume. See `ObservationPath`.
            path: .hid
        )
        diagnostics.append(entry)
        onEvent?(entry)
    }
}
