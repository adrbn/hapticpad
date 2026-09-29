import CMultitouch
import TexturCore

/// A Force Touch surface found on this Mac.
struct Trackpad: Identifiable, Equatable, Sendable {
    let id: UInt64
    let isBuiltIn: Bool
    let surface: SurfaceSize

    var label: String { isBuiltIn ? "Built-in trackpad" : "External trackpad" }
}

/// Finds haptic-capable trackpads through the private MultitouchSupport bridge.
enum TrackpadDiscovery {
    static var isFrameworkAvailable: Bool { tx_multitouch_available() }

    static func trackpads() -> [Trackpad] {
        let capacity: Int32 = 8
        var buffer = [TXDeviceInfo](repeating: TXDeviceInfo(), count: Int(capacity))
        let found = Int(tx_multitouch_list_devices(&buffer, capacity))
        return buffer.prefix(min(found, Int(capacity))).map { info in
            Trackpad(
                id: info.deviceID,
                isBuiltIn: info.builtIn,
                surface: SurfaceSize(width: Double(info.widthMM), height: Double(info.heightMM))
            )
        }
    }
}
