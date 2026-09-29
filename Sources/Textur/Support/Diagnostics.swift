import CMultitouch
import Foundation
import TexturCore

/// `Textur --diagnose`: prints what the app can see, plays each strength once
/// and counts contact frames while the user touches the trackpad.
enum Diagnostics {
    static let listenDuration: TimeInterval = 3

    static func run() -> Int32 {
        print("Textur diagnostics")
        print("MultitouchSupport available: \(TrackpadDiscovery.isFrameworkAvailable)")
        let trackpads = TrackpadDiscovery.trackpads()
        print("Haptic trackpads found: \(trackpads.count)")
        let actuators = HapticActuators()
        var allPassed = !trackpads.isEmpty
        for trackpad in trackpads {
            let size = String(format: "%.1f x %.1f mm", trackpad.surface.width, trackpad.surface.height)
            print("- \(trackpad.label), id \(trackpad.id), \(size)")
            for strength in PulseStrength.allCases {
                let passed = actuators.probe(strength, on: trackpad.id)
                allPassed = allPassed && passed
                print("  \(strength) (waveform \(strength.actuationID)): \(passed ? "ok" : "FAILED")")
                Thread.sleep(forTimeInterval: 0.35)
            }
        }
        if !trackpads.isEmpty {
            print("Touch the trackpad now (\(Int(listenDuration)) s)...")
            let frames = countFrames(for: listenDuration)
            print("Contact frames received: \(frames)\(frames == 0 ? " (none: did a finger touch the trackpad?)" : "")")
        }
        print(allPassed ? "Result: haptics ready" : "Result: haptics unavailable, sounds still work")
        return allPassed ? 0 : 1
    }

    /// Streams contact frames for a while and returns how many arrived.
    private static func countFrames(for duration: TimeInterval) -> Int {
        let counter = FrameCounter()
        let reference = Unmanaged.passRetained(counter)
        if tx_multitouch_start(frameCountingCallback, reference.toOpaque()) > 0 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: duration))
        }
        tx_multitouch_stop()
        reference.release()
        return counter.value
    }
}

private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private let frameCountingCallback: TXFrameHandler = { _, _, _, _, context in
    guard let context else { return }
    Unmanaged<FrameCounter>.fromOpaque(context).takeUnretainedValue().increment()
}
