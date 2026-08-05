import CoreAudio
import Foundation
import NoBudsMusicCore
import os

/// Reports whether anything is currently playing audio on the default output
/// device, and calls back when that changes.
///
/// This is what makes the sink switchable. `TECH_RESEARCH.md` M19 and M21 showed
/// there is no fixed Now Playing state that is correct in both situations: the
/// app has to claim the destination when nothing is playing and release it when
/// something is. "Is anything playing" is not exposed by MediaRemote's public
/// API, but CoreAudio answers it directly with
/// `kAudioDevicePropertyDeviceIsRunningSomewhere`.
///
/// Event-driven via `AudioObjectAddPropertyListenerBlock` — no timer, no
/// polling. Passivity is a constraint here, not a preference (ADR 0003).
///
/// The answer comes from the per-process audio objects
/// (`kAudioHardwarePropertyProcessObjectList` +
/// `kAudioProcessPropertyIsRunningOutput`), which name the process that is
/// playing rather than merely reporting that the device is in use. The
/// device-level property is the change *trigger*; the process list is the
/// *answer*. On a system too old for process objects the device-level answer is
/// used instead.
///
/// Known imprecision: this reports *any* audio output, including a notification
/// sound or a UI click. A blip of unrelated audio briefly looks like playback.
/// The cost is that the app releases the destination for that moment, which
/// risks nothing worse than a launch it would otherwise have prevented.
final class AudioActivityMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "audio")
    private let lock = NSLock()
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// Called when audio starts or stops. Not on the main thread.
    var onChange: (@Sendable (Bool) -> Void)?

    // Fresh values rather than shared mutable statics: the CoreAudio calls take
    // a mutable pointer, and a `static var` here is global mutable state that
    // strict concurrency rejects.
    private static func runningAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        guard let device = Self.defaultOutputDevice() else {
            logger.error("no default output device; audio activity is unknown")
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let playing = Self.isRunning(device)
            self.logger.debug("audio activity changed: \(playing, privacy: .public)")
            self.onChange?(playing)
        }

        var address = Self.runningAddress()
        let status = AudioObjectAddPropertyListenerBlock(device, &address, nil, block)
        guard status == noErr else {
            logger.error("failed to observe audio activity: \(status, privacy: .public)")
            return
        }

        lock.withLock {
            deviceID = device
            listenerBlock = block
        }
        logger.info("observing audio activity")
    }

    func stop() {
        let (device, block) = lock.withLock {
            () -> (AudioObjectID, AudioObjectPropertyListenerBlock?) in
            defer {
                deviceID = AudioObjectID(kAudioObjectUnknown)
                listenerBlock = nil
            }
            return (deviceID, listenerBlock)
        }
        guard let block, device != AudioObjectID(kAudioObjectUnknown) else { return }
        var address = Self.runningAddress()
        AudioObjectRemovePropertyListenerBlock(device, &address, nil, block)
    }

    /// Whether any process other than this one is playing audio.
    var isAudioPlaying: Bool {
        activeOutputDescription != nil
    }

    /// Who is producing audio output, for the log. `nil` when nothing is.
    var activeOutputDescription: String? {
        if let byProcess = Self.processRunningOutput() {
            return byProcess.isEmpty ? nil : byProcess.joined(separator: ", ")
        }
        // Process objects need macOS 14.2. Fall back to the device-level
        // answer, which cannot say who is playing but does say whether anyone
        // is.
        guard let device = Self.defaultOutputDevice() else { return nil }
        return Self.isRunning(device) ? "output device (no process detail)" : nil
    }

    /// Bundle identifiers of processes currently running audio output, or `nil`
    /// when the process-object API is unavailable.
    ///
    /// This process is excluded: it never produces audio today, but a sink that
    /// counted itself would deactivate itself.
    private static func processRunningOutput() -> [String]? {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard
            AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr,
            size > 0
        else { return nil }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard
            AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &ids) == noErr
        else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return ids.compactMap { id -> String? in
            guard isRunningOutput(id), pid(of: id) != ownPID else { return nil }
            return bundleID(of: id) ?? "pid \(pid(of: id) ?? -1)"
        }
    }

    private static func isRunningOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    private static func pid(of id: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func bundleID(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Read into raw storage rather than a `CFString?` variable: taking a
        // mutable pointer to a Swift optional holding an object reference is
        // undefined, and the compiler rejects it.
        var size = UInt32(MemoryLayout<UnsafeRawPointer?>.size)
        var raw: UnsafeRawPointer?
        let status = withUnsafeMutablePointer(to: &raw) { pointer -> OSStatus in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let raw else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeRetainedValue() as String
    }

    // MARK: - Queries

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultOutputAddress()
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func isRunning(_ device: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = runningAddress()
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &running
        )
        // Unknown means "do not claim the destination": failing towards not
        // interfering is the safer direction.
        guard status == noErr else { return true }
        return running != 0
    }
}
