import AppKit
import CoreGraphics
import TexturCore

/// Listens to key presses for typing sounds.
///
/// Uses a listen-only event tap, which macOS gates behind Input Monitoring.
/// Only the key family (letter, space, return, delete) is derived from each
/// event; characters are never read, stored or sent anywhere.
@MainActor
final class KeyboardMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@MainActor (SoundTrigger) -> Void)?

    var isRunning: Bool { tap != nil }

    isolated deinit {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt (first time) or does nothing if already decided.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns false when the tap could not be created, usually for lack of permission.
    @discardableResult
    func start(onKey: @escaping @MainActor (SoundTrigger) -> Void) -> Bool {
        guard tap == nil else { return true }
        handler = onKey
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            handler = nil
            return false
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        handler = nil
    }

    fileprivate func handle(type: CGEventType, keyCode: Int64, isRepeat: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown where !isRepeat:
            handler?(SoundTrigger(keyCode: keyCode))
        default:
            break
        }
    }
}

/// The tap is attached to the main run loop, so this runs on the main thread.
private func keyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        MainActor.assumeIsolated { monitor.handle(type: type, keyCode: keyCode, isRepeat: isRepeat) }
    }
    return Unmanaged.passUnretained(event)
}
