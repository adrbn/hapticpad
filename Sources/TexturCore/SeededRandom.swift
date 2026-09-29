/// A tiny deterministic generator (SplitMix64), so textures are reproducible in tests.
///
/// Immutable: each draw returns the generator to use next.
public struct SeededRandom: Sendable, Equatable {
    private let state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public func nextBits() -> (SeededRandom, UInt64) {
        let advanced = state &+ 0x9E37_79B9_7F4A_7C15
        var mixed = advanced
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return (SeededRandom(seed: advanced), mixed)
    }

    /// A value in 0..<1.
    public func nextUnit() -> (SeededRandom, Double) {
        let (next, bits) = nextBits()
        return (next, Double(bits >> 11) / Double(1 << 53))
    }

    /// A value in -1..<1.
    public func nextSigned() -> (SeededRandom, Double) {
        let (next, unit) = nextUnit()
        return (next, unit * 2 - 1)
    }
}
