/// A 2D vector in millimetres on the trackpad surface.
public struct Vector2: Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(x: 0, y: 0)

    public var length: Double { (x * x + y * y).squareRoot() }

    /// Length after scaling each axis independently, used for directional materials.
    public func weightedLength(_ weights: Vector2) -> Double {
        Vector2(x: x * weights.x, y: y * weights.y).length
    }

    public static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    /// Mean of a set of points, or zero for an empty set.
    public static func centroid(_ points: [Vector2]) -> Vector2 {
        guard !points.isEmpty else { return .zero }
        return points.reduce(.zero, +) * (1 / Double(points.count))
    }
}
