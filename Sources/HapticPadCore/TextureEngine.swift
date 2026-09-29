/// Knobs that change how a material plays without changing the material itself.
public struct TextureTuning: Equatable, Sendable {
    public let strength: HapticStrength
    /// Multiplies the material spacing: below 1 is finer, above 1 is coarser.
    public let grainScale: Double
    /// Extra spacing multiplier per input, e.g. wider grains while scrolling.
    public let spacingFactor: Double

    public init(strength: HapticStrength, grainScale: Double, spacingFactor: Double = 1) {
        self.strength = strength
        self.grainScale = grainScale
        self.spacingFactor = spacingFactor
    }
}

/// Converts finger travel into haptic grains for one material.
///
/// Immutable: `advance` returns the engine to use next along with the pulses to play.
public struct TextureEngine: Sendable {
    /// The actuator needs a few milliseconds per waveform; closer grains are dropped.
    public static let minimumGrainInterval = 0.010
    /// Travel below this (mm) is buffered, so sensor noise under a resting finger cancels out.
    public static let noiseFloor = 0.08
    /// Shortest allowed distance between two grains, in millimetres.
    public static let minimumGap = 0.15
    /// Longest travel accounted for in a single frame, guarding against glitches.
    public static let maximumStep = 50.0

    public let material: Material
    public let tuning: TextureTuning
    private let random: SeededRandom
    private let pending: Vector2
    private let travelled: Double
    private let nextGap: Double
    private let grainCount: Int
    private let lastGrainTime: Double

    public init(material: Material, tuning: TextureTuning, seed: UInt64) {
        let (random, gap) = Self.drawGap(material: material, tuning: tuning, random: SeededRandom(seed: seed))
        self.init(
            material: material, tuning: tuning, random: random, pending: .zero,
            travelled: 0, nextGap: gap, grainCount: 0, lastGrainTime: -.infinity
        )
    }

    private init(
        material: Material, tuning: TextureTuning, random: SeededRandom, pending: Vector2,
        travelled: Double, nextGap: Double, grainCount: Int, lastGrainTime: Double
    ) {
        self.material = material
        self.tuning = tuning
        self.random = random
        self.pending = pending
        self.travelled = travelled
        self.nextGap = nextGap
        self.grainCount = grainCount
        self.lastGrainTime = lastGrainTime
    }

    public func advance(by delta: Vector2, at timestamp: Double) -> (TextureEngine, [Pulse]) {
        let accumulated = pending + delta
        guard accumulated.length >= Self.noiseFloor else {
            return (copy(pending: accumulated), [])
        }

        var travel = travelled + min(accumulated.weightedLength(material.axisWeights), Self.maximumStep)
        var gap = nextGap
        var generator = random
        var count = grainCount
        var crossed: [[Pulse]] = []
        while travel >= gap {
            travel -= gap
            count += 1
            let (afterGrain, grain) = chooseGrain(index: count, random: generator)
            let (afterGap, newGap) = Self.drawGap(material: material, tuning: tuning, random: afterGrain)
            generator = afterGap
            gap = newGap
            if let grain {
                crossed.append(grain)
            }
        }

        let canPlay = timestamp - lastGrainTime >= Self.minimumGrainInterval
        let chosen = canPlay ? Self.strongest(crossed) : nil
        let pulses = chosen?.map { $0.shifted(by: tuning.strength.offset) } ?? []
        let next = TextureEngine(
            material: material, tuning: tuning, random: generator, pending: .zero,
            travelled: travel, nextGap: gap, grainCount: count,
            lastGrainTime: pulses.isEmpty ? lastGrainTime : timestamp
        )
        return (next, pulses)
    }

    /// Forgets partial travel, e.g. when the finger lifts.
    public func reset() -> TextureEngine {
        TextureEngine(
            material: material, tuning: tuning, random: random, pending: .zero,
            travelled: 0, nextGap: nextGap, grainCount: grainCount, lastGrainTime: lastGrainTime
        )
    }

    /// Same random stream, new material or tuning.
    public func reconfigured(material: Material, tuning: TextureTuning) -> TextureEngine {
        let (random, gap) = Self.drawGap(material: material, tuning: tuning, random: random)
        return TextureEngine(
            material: material, tuning: tuning, random: random, pending: .zero,
            travelled: 0, nextGap: gap, grainCount: 0, lastGrainTime: lastGrainTime
        )
    }

    private func copy(pending: Vector2) -> TextureEngine {
        TextureEngine(
            material: material, tuning: tuning, random: random, pending: pending,
            travelled: travelled, nextGap: nextGap, grainCount: grainCount, lastGrainTime: lastGrainTime
        )
    }

    private func chooseGrain(index: Int, random: SeededRandom) -> (SeededRandom, [Pulse]?) {
        let (afterSkip, skipRoll) = random.nextUnit()
        if skipRoll < material.skipChance {
            return (afterSkip, nil)
        }
        guard let accent = material.accent else {
            return (afterSkip, material.grain)
        }
        let (afterAccent, accentRoll) = afterSkip.nextUnit()
        let periodic = accent.every > 0 && index.isMultiple(of: accent.every)
        let accented = periodic || accentRoll < accent.chance
        return (afterAccent, accented ? accent.grain : material.grain)
    }

    private static func drawGap(material: Material, tuning: TextureTuning, random: SeededRandom) -> (SeededRandom, Double) {
        let (next, variation) = random.nextSigned()
        let mean = material.spacing * tuning.grainScale * tuning.spacingFactor
        return (next, max(mean * (1 + material.jitter * variation), minimumGap))
    }

    private static func strongest(_ grains: [[Pulse]]) -> [Pulse]? {
        grains.reduce(nil) { best, grain in
            guard let best else { return grain }
            let bestPeak = best.map(\.strength).max() ?? .whisper
            let grainPeak = grain.map(\.strength).max() ?? .whisper
            return grainPeak > bestPeak ? grain : best
        }
    }
}
