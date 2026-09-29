import Foundation
import IOKit

/// Reports multitouch devices that appear or disappear, such as a Magic Trackpad
/// that connects over Bluetooth a few seconds after HapticPad launched at login.
@MainActor
final class TrackpadWatcher {
    /// MultitouchSupport lists a new device a moment after IOKit matches it, so look twice.
    static let settleDelays: [TimeInterval] = [1, 3]

    private let onChange: @MainActor () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        iterators.forEach { IOObjectRelease($0) }
        if let port {
            IONotificationPortDestroy(port)
        }
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, notification, IOServiceMatching("AppleMultitouchDevice"), deviceCallback, context, &iterator
            )
            guard result == KERN_SUCCESS else { continue }
            // Draining the iterator arms the notification; devices present at launch are already known.
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let port {
            IONotificationPortDestroy(port)
        }
        port = nil
    }

    fileprivate func devicesChanged(_ iterator: io_iterator_t) {
        Self.drain(iterator)
        for delay in Self.settleDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.onChange()
            }
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}

/// Runs on the main queue, where the notification port delivers.
private func deviceCallback(context: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    // The pointer only names the watcher, which lives on the main actor like this callback.
    guard let address = context.map(UInt.init(bitPattern:)) else { return }
    MainActor.assumeIsolated {
        guard let context = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<TrackpadWatcher>.fromOpaque(context).takeUnretainedValue().devicesChanged(iterator)
    }
}
