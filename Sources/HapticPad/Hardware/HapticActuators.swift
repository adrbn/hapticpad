import CMultitouch
import Dispatch
import HapticPadCore
import os

/// Plays pulses on the Taptic Engine of each trackpad.
///
/// Actuator handles are opened lazily and only touched on `queue`. A failed
/// actuation closes the handle and retries once, which covers handles that go
/// stale across sleep and wake.
final class HapticActuators: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hapticpad.actuators", qos: .userInteractive)
    private let log = Logger(subsystem: "HapticPad", category: "actuators")
    private var handles: [UInt64: UnsafeMutableRawPointer] = [:]

    deinit {
        handles.values.forEach(hp_actuator_close)
    }

    /// Schedules a grain (a short sequence of pulses) on one trackpad.
    func play(_ pulses: [Pulse], on deviceID: UInt64) {
        guard !pulses.isEmpty else { return }
        queue.async { [self] in
            for pulse in pulses {
                if pulse.delay <= 0 {
                    fire(pulse.strength, on: deviceID)
                } else {
                    queue.asyncAfter(deadline: .now() + pulse.delay) { [self] in
                        fire(pulse.strength, on: deviceID)
                    }
                }
            }
        }
    }

    /// Plays on every given trackpad, e.g. for a material preview.
    func play(_ pulses: [Pulse], on trackpads: [Trackpad]) {
        trackpads.forEach { play(pulses, on: $0.id) }
    }

    /// Closes every handle; the next pulse reopens what it needs.
    func reset() {
        queue.async { [self] in
            handles.values.forEach(hp_actuator_close)
            handles.removeAll()
        }
    }

    /// Synchronously checks that a trackpad's actuator accepts a waveform.
    func probe(_ strength: PulseStrength, on deviceID: UInt64) -> Bool {
        queue.sync { fire(strength, on: deviceID) }
    }

    @discardableResult
    private func fire(_ strength: PulseStrength, on deviceID: UInt64) -> Bool {
        if actuate(strength, on: deviceID) {
            return true
        }
        close(deviceID)
        let retried = actuate(strength, on: deviceID)
        if !retried {
            log.error("Actuation \(strength.actuationID) failed on device \(deviceID, privacy: .public)")
        }
        return retried
    }

    private func actuate(_ strength: PulseStrength, on deviceID: UInt64) -> Bool {
        guard let handle = handle(for: deviceID) else { return false }
        return hp_actuator_actuate(handle, strength.actuationID, 0, 0)
    }

    private func handle(for deviceID: UInt64) -> UnsafeMutableRawPointer? {
        if let existing = handles[deviceID] {
            return existing
        }
        guard let opened = hp_actuator_open(deviceID) else {
            log.error("Could not open the actuator of device \(deviceID, privacy: .public)")
            return nil
        }
        handles[deviceID] = opened
        return opened
    }

    private func close(_ deviceID: UInt64) {
        if let handle = handles.removeValue(forKey: deviceID) {
            hp_actuator_close(handle)
        }
    }
}
