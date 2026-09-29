import AppKit

/// Reports mouse and trackpad clicks anywhere on screen. Needs no permission.
@MainActor
final class ClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isRunning: Bool { globalMonitor != nil }

    func start(onClick: @escaping @MainActor () -> Void) {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            MainActor.assumeIsolated { onClick() }
        }
        // Global monitors skip our own windows, so listen locally too.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { onClick() }
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }
}
