/// Where a finger is in its contact lifecycle.
public enum TouchPhase: Equatable, Sendable {
    /// Near or leaving the surface without pressing on it.
    case hovering
    /// In contact with the surface.
    case touching
    /// The frame in which the finger leaves the surface.
    case lifting

    /// Maps the trackpad firmware's path stage (see `HPTouchState`).
    public init(rawState: Int32) {
        switch rawState {
        case 3, 4: self = .touching
        case 5: self = .lifting
        default: self = .hovering
        }
    }
}

/// Physical size of a trackpad surface in millimetres.
public struct SurfaceSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    /// A 13-inch MacBook trackpad, used when the device does not report its size.
    public static let fallback = SurfaceSize(validWidth: 127, height: 78)

    public init(width: Double, height: Double) {
        if width > 0, height > 0 {
            self.init(validWidth: width, height: height)
        } else {
            self = .fallback
        }
    }

    private init(validWidth: Double, height: Double) {
        self.width = validWidth
        self.height = height
    }
}

/// One finger on the surface, positioned in millimetres.
public struct Touch: Equatable, Sendable {
    public let id: Int32
    public let position: Vector2
    public let phase: TouchPhase

    public init(id: Int32, position: Vector2, phase: TouchPhase) {
        self.id = id
        self.position = position
        self.phase = phase
    }

    /// Builds a touch from the normalized coordinates reported by the trackpad.
    public init(id: Int32, normalizedX: Double, normalizedY: Double, surface: SurfaceSize, rawState: Int32) {
        self.init(
            id: id,
            position: Vector2(x: normalizedX * surface.width, y: normalizedY * surface.height),
            phase: TouchPhase(rawState: rawState)
        )
    }
}

/// Every finger reported by one trackpad at one instant.
public struct TouchFrame: Equatable, Sendable {
    public let timestamp: Double
    public let touches: [Touch]

    public init(timestamp: Double, touches: [Touch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}
