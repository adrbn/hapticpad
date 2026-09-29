/// What the fingers did between two frames, as far as feedback is concerned.
public enum GestureEvent: Equatable, Sendable {
    /// One finger moved the pointer.
    case pointer(delta: Vector2, timestamp: Double)
    /// Two fingers moved together.
    case scroll(delta: Vector2, timestamp: Double)
    /// A finger landed on the surface (at most two fingers down).
    case touchDown(timestamp: Double)
}
