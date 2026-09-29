import Foundation

/// Keeps App Nap from throttling HapticPad while it gives feedback. A grain or a
/// click sound that arrives late no longer feels attached to the finger.
@MainActor
final class LatencyActivity {
    private var token: NSObjectProtocol?

    func setActive(_ active: Bool) {
        if active, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Trackpad haptics and sounds follow the finger"
            )
        } else if !active, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
