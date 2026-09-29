/// Turns raw trackpad frames into pointer, scroll and touch-down events.
///
/// Immutable: `consume` returns the interpreter to use for the next frame.
/// One-finger travel is pointer movement, two-finger travel is scrolling, and
/// three or more fingers are left alone because they drive system gestures.
public struct GestureInterpreter: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Shortest time, in seconds, between two touch-downs, so fingers landing together tick once.
        public let landingInterval: Double
        /// Most fingers down for a landing to count; more is a system gesture.
        public let landingMaxFingers: Int
        /// Of two fingers, one that travels less than this fraction of the other is resting
        /// (typically the thumb during a click-drag), and the other one drives the pointer.
        public let restingFingerRatio: Double

        public init(landingInterval: Double = 0.1, landingMaxFingers: Int = 2, restingFingerRatio: Double = 0.25) {
            self.landingInterval = landingInterval
            self.landingMaxFingers = landingMaxFingers
            self.restingFingerRatio = restingFingerRatio
        }
    }

    public let configuration: Configuration
    private let lastPositions: [Int32: Vector2]
    private let lastLanding: Double?

    public init(configuration: Configuration = Configuration()) {
        self.init(configuration: configuration, lastPositions: [:], lastLanding: nil)
    }

    private init(configuration: Configuration, lastPositions: [Int32: Vector2], lastLanding: Double?) {
        self.configuration = configuration
        self.lastPositions = lastPositions
        self.lastLanding = lastLanding
    }

    public func consume(_ frame: TouchFrame) -> (GestureInterpreter, [GestureEvent]) {
        let positions = Dictionary(
            frame.touches.filter { $0.phase == .touching }.map { ($0.id, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )
        let landing = landingEvent(from: positions, timestamp: frame.timestamp)
        let movement = movementEvent(from: positions, timestamp: frame.timestamp)
        let next = GestureInterpreter(
            configuration: configuration,
            lastPositions: positions,
            lastLanding: landing == nil ? lastLanding : frame.timestamp
        )
        return (next, [landing, movement].compactMap { $0 })
    }

    /// A finger landed. Haptics are only felt while a finger touches the surface,
    /// so this is the moment a tap can be confirmed, not when it lifts.
    private func landingEvent(from positions: [Int32: Vector2], timestamp: Double) -> GestureEvent? {
        let arrived = positions.keys.contains { lastPositions[$0] == nil }
        guard arrived, positions.count <= configuration.landingMaxFingers else { return nil }
        if let lastLanding, timestamp - lastLanding < configuration.landingInterval { return nil }
        return .touchDown(timestamp: timestamp)
    }

    /// Movement is only reported while the same fingers stay down, so a finger
    /// landing or lifting never reads as a jump across the surface.
    private func movementEvent(from positions: [Int32: Vector2], timestamp: Double) -> GestureEvent? {
        guard !positions.isEmpty, Set(positions.keys) == Set(lastPositions.keys) else { return nil }
        let ids = positions.keys.sorted()
        let travels = ids.compactMap { id in positions[id].flatMap { now in lastPositions[id].map { now - $0 } } }
        let delta = Vector2.centroid(travels)
        guard delta != .zero else { return nil }
        switch travels.count {
        case 1:
            return .pointer(delta: delta, timestamp: timestamp)
        case 2:
            let ordered = travels.sorted { $0.length < $1.length }
            if ordered[0].length < ordered[1].length * configuration.restingFingerRatio {
                return .pointer(delta: ordered[1], timestamp: timestamp)
            }
            return .scroll(delta: delta, timestamp: timestamp)
        default:
            return nil
        }
    }
}
