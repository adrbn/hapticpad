import Testing
@testable import HapticPadCore

private func material(
    spacing: Double = 2,
    jitter: Double = 0,
    axisWeights: Vector2 = Vector2(x: 1, y: 1),
    grain: [Pulse] = [Pulse(strength: .whisper)],
    accent: Material.Accent? = nil,
    skipChance: Double = 0
) -> Material {
    Material(
        id: .linen,
        name: "Test",
        summary: "Test material",
        spacing: spacing,
        jitter: jitter,
        axisWeights: axisWeights,
        grain: grain,
        accent: accent,
        skipChance: skipChance
    )
}

/// Moves by `step` for `count` frames, 10 ms apart, collecting every pulse batch.
private func drag(
    _ engine: TextureEngine,
    step: Vector2,
    count: Int,
    startTime: Double = 0,
    interval: Double = 0.010
) -> (TextureEngine, [[Pulse]]) {
    var current = engine
    var batches: [[Pulse]] = []
    for index in 0..<count {
        let (next, pulses) = current.advance(by: step, at: startTime + Double(index) * interval)
        current = next
        if !pulses.isEmpty {
            batches.append(pulses)
        }
    }
    return (current, batches)
}

@Suite("TextureEngine")
struct TextureEngineTests {
    private let medium = TextureTuning(strength: .medium, grainScale: 1)

    @Test func travelShorterThanSpacingIsSilent() {
        let engine = TextureEngine(material: material(spacing: 2), tuning: medium, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 3)
        #expect(batches.isEmpty)
    }

    @Test func crossingTheSpacingPlaysOneGrain() {
        let engine = TextureEngine(material: material(spacing: 2), tuning: medium, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 4)
        #expect(batches == [[Pulse(strength: .whisper)]])
    }

    @Test func grainRateFollowsDistance() {
        let engine = TextureEngine(material: material(spacing: 1), tuning: medium, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 40)
        #expect(batches.count == 20)
    }

    @Test func sensorNoiseAroundARestingFingerIsIgnored() {
        var engine = TextureEngine(material: material(spacing: 0.3), tuning: medium, seed: 1)
        var total = 0
        for index in 0..<400 {
            let sign: Double = index.isMultiple(of: 2) ? 1 : -1
            let (next, pulses) = engine.advance(by: Vector2(x: 0.03 * sign, y: -0.02 * sign), at: Double(index) * 0.01)
            engine = next
            total += pulses.count
        }
        #expect(total == 0)
    }

    @Test func directionalMaterialIgnoresMovementAlongItsRidges() {
        let ridges = material(spacing: 1, axisWeights: Vector2(x: 1, y: 0))
        let engine = TextureEngine(material: ridges, tuning: medium, seed: 1)
        let (_, vertical) = drag(engine, step: Vector2(x: 0, y: 0.5), count: 40)
        let (_, horizontal) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 40)
        #expect(vertical.isEmpty)
        #expect(horizontal.count == 20)
    }

    @Test func fastSwipeCollapsesToOneGrainPerFrame() {
        let engine = TextureEngine(material: material(spacing: 0.5), tuning: medium, seed: 1)
        let (_, pulses) = engine.advance(by: Vector2(x: 10, y: 0), at: 0)
        #expect(pulses == [Pulse(strength: .whisper)])
    }

    @Test func grainsCloserThanTheActuatorCanPlayAreDropped() {
        let engine = TextureEngine(material: material(spacing: 0.5), tuning: medium, seed: 1)
        let (afterFirst, first) = engine.advance(by: Vector2(x: 1, y: 0), at: 0.000)
        let (_, second) = afterFirst.advance(by: Vector2(x: 1, y: 0), at: 0.004)
        #expect(first.count == 1)
        #expect(second.isEmpty)
    }

    @Test func strengthShiftsEveryPulse() {
        let strong = TextureTuning(strength: .strong, grainScale: 1)
        let engine = TextureEngine(material: material(spacing: 1), tuning: strong, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 2)
        #expect(batches == [[Pulse(strength: .soft)]])
    }

    @Test func grainScaleStretchesTheSpacing() {
        let coarse = TextureTuning(strength: .medium, grainScale: 2)
        let engine = TextureEngine(material: material(spacing: 1), tuning: coarse, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 40)
        #expect(batches.count == 10)
    }

    @Test func spacingFactorStretchesTheSpacing() {
        let scroll = TextureTuning(strength: .medium, grainScale: 1, spacingFactor: 4)
        let engine = TextureEngine(material: material(spacing: 1), tuning: scroll, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 40)
        #expect(batches.count == 5)
    }

    @Test func periodicAccentReplacesEveryNthGrain() {
        let accent = Material.Accent(every: 3, chance: 0, grain: [Pulse(strength: .firm)])
        let engine = TextureEngine(material: material(spacing: 1, accent: accent), tuning: medium, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 1, y: 0), count: 6, interval: 0.02)
        let strengths = batches.map { $0.first?.strength }
        #expect(strengths == [.whisper, .whisper, .firm, .whisper, .whisper, .firm])
    }

    @Test func certainSkipSilencesEveryGrain() {
        let engine = TextureEngine(material: material(spacing: 1, skipChance: 1), tuning: medium, seed: 1)
        let (_, batches) = drag(engine, step: Vector2(x: 1, y: 0), count: 20, interval: 0.02)
        #expect(batches.isEmpty)
    }

    @Test func jitterVariesSpacingButKeepsTheAverage() {
        let engine = TextureEngine(material: material(spacing: 1, jitter: 0.8), tuning: medium, seed: 7)
        let (_, batches) = drag(engine, step: Vector2(x: 0.25, y: 0), count: 800, interval: 0.02)
        #expect((170...230).contains(batches.count))
    }

    @Test func sameSeedGivesTheSameTexture() {
        let rough = material(spacing: 0.7, jitter: 0.9, skipChance: 0.3)
        let first = drag(TextureEngine(material: rough, tuning: medium, seed: 42), step: Vector2(x: 0.3, y: 0.1), count: 300)
        let second = drag(TextureEngine(material: rough, tuning: medium, seed: 42), step: Vector2(x: 0.3, y: 0.1), count: 300)
        #expect(first.1 == second.1)
    }

    @Test func resettingForgetsPartialTravel() {
        let engine = TextureEngine(material: material(spacing: 2), tuning: medium, seed: 1)
        let (moved, _) = drag(engine, step: Vector2(x: 0.5, y: 0), count: 3)
        let (_, batches) = drag(moved.reset(), step: Vector2(x: 0.5, y: 0), count: 3, startTime: 1)
        #expect(batches.isEmpty)
    }
}

@Suite("Pulses")
struct PulseTests {
    @Test func strengthsMapToTheActuatorWaveforms() {
        #expect(PulseStrength.whisper.actuationID == 1)
        #expect(PulseStrength.soft.actuationID == 5)
        #expect(PulseStrength.firm.actuationID == 4)
        #expect(PulseStrength.strong.actuationID == 6)
    }

    @Test func shiftingClampsToTheAvailableRange() {
        #expect(PulseStrength.whisper.shifted(by: -2) == .whisper)
        #expect(PulseStrength.soft.shifted(by: 1) == .firm)
        #expect(PulseStrength.firm.shifted(by: 5) == .strong)
    }

    @Test func hapticStrengthOffsetsAreOrdered() {
        let offsets = HapticStrength.allCases.map(\.offset)
        #expect(offsets == offsets.sorted())
        #expect(HapticStrength.medium.offset == 0)
    }
}
