import Foundation

/// Texture sound: one short, quiet sound per grain, voiced after the material,
/// so a texture can be heard as well as felt.
extension SoundSynth {
    public static let grainVariantCount = 4

    /// Playback level of a grain, before the volume setting. Well under the clicks,
    /// since grains come dozens of times a second.
    public static func grainLevel(for strength: PulseStrength) -> Double {
        switch strength {
        case .whisper: 0.35
        case .soft: 0.5
        case .firm: 0.7
        case .strong: 0.9
        }
    }

    public static func renderGrain(material: MaterialID, variant: Int, sampleRate: Double) -> [Float] {
        let count = grainVariantCount
        let index = ((variant % count) + count) % count
        let variation = Double(index) / Double(count - 1) * 2 - 1
        let seed = grainSeed(material: material, index: index)
        let (samples, gain): ([Double], Double) = switch material {
        case .linen: linenGrain(variation: variation, seed: seed, sampleRate: sampleRate)
        case .corduroy: corduroyGrain(variation: variation, seed: seed, sampleRate: sampleRate)
        case .sand: sandGrain(variation: variation, seed: seed, sampleRate: sampleRate)
        case .wood: woodGrain(variation: variation, seed: seed, sampleRate: sampleRate)
        case .gravel: gravelGrain(variation: variation, seed: seed, sampleRate: sampleRate)
        case .knurl: knurlGrain(variation: variation, seed: seed, sampleRate: sampleRate)
        }
        return finish(samples, gain: gain, sampleRate: sampleRate)
    }

    // MARK: - Materials

    /// A soft brush of thread: band-limited noise that fades in a few milliseconds.
    private static func linenGrain(variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let times = timeline(duration: 0.02, sampleRate: sampleRate)
        let brush = lowPass(highPass(noise(count: times.count, seed: seed), amount: 0.25), amount: 0.5)
        let decay = 0.0025 * (1 + 0.2 * variation)
        return (zip(times, brush).map { t, value in value * exp(-t / decay) }, 0.45)
    }

    /// A low, padded ridge.
    private static func corduroyGrain(variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let times = timeline(duration: 0.04, sampleRate: sampleRate)
        let base = 150 * (1 + 0.1 * variation)
        let thump = integratedSine(times: times, sampleRate: sampleRate) { t in base * (0.8 + 0.2 * exp(-t / 0.006)) }
        let fabric = lowPass(noise(count: times.count, seed: seed), amount: 0.08)
        let samples = zip(times, zip(thump, fabric)).map { t, parts in
            parts.0 * exp(-t / 0.007) + 0.6 * parts.1 * exp(-t / 0.003)
        }
        return (samples, 0.6)
    }

    /// A bright speck, sometimes followed by a second one.
    private static func sandGrain(variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let times = timeline(duration: 0.015, sampleRate: sampleRate)
        let hiss = highPass(noise(count: times.count, seed: seed), amount: 0.5)
        let echo = 0.0035 + 0.0015 * variation
        let samples = zip(times, hiss).map { t, value in
            value * (exp(-t / 0.0007) + 0.5 * delayedEnvelope(at: t, start: echo, decay: 0.0006))
        }
        return (samples, 0.4)
    }

    /// A hollow tock: two resonant modes over a short body.
    private static func woodGrain(variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let times = timeline(duration: 0.05, sampleRate: sampleRate)
        let tune = 1 + 0.06 * variation
        let knock = noise(count: times.count, seed: seed)
        let samples = zip(times, knock).map { t, click in
            let mode = sin(2 * .pi * 950 * tune * t) * exp(-t / 0.005)
                + 0.4 * sin(2 * .pi * 2300 * tune * t) * exp(-t / 0.002)
            let body = 0.5 * sin(2 * .pi * 320 * tune * t) * exp(-t / 0.009)
            return mode + body + 0.5 * click * exp(-t / 0.0004)
        }
        return (samples, 0.6)
    }

    /// A crunch: a few gritty bursts over a small thud.
    private static func gravelGrain(variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let times = timeline(duration: 0.035, sampleRate: sampleRate)
        let grit = lowPass(noise(count: times.count, seed: seed), amount: 0.35)
        let bursts: [(start: Double, level: Double)] = [
            (0, 1),
            (0.004 + 0.0015 * variation, 0.6),
            (0.009 + 0.003 * variation, 0.35),
        ]
        let samples = zip(times, grit).map { t, value in
            let envelope = bursts.reduce(0) { sum, burst in
                sum + burst.level * delayedEnvelope(at: t, start: burst.start, decay: 0.0015)
            }
            return value * envelope + 0.3 * sin(2 * .pi * 110 * t) * exp(-t / 0.006)
        }
        return (samples, 0.6)
    }

    /// A small metallic tick: inharmonic partials that ring very briefly.
    private static func knurlGrain(variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let times = timeline(duration: 0.025, sampleRate: sampleRate)
        let tune = 1 + 0.03 * variation
        let partials: [(frequency: Double, level: Double, decay: Double)] = [
            (3200, 1, 0.003),
            (5150, 0.6, 0.002),
            (7900, 0.4, 0.0015),
        ]
        let click = noise(count: times.count, seed: seed)
        let samples = zip(times, click).map { t, value in
            let ring = partials.reduce(0) { sum, partial in
                sum + partial.level * sin(2 * .pi * partial.frequency * tune * t) * exp(-t / partial.decay)
            }
            return ring + 0.4 * value * exp(-t / 0.0003)
        }
        return (samples, 0.45)
    }

    // MARK: - Helpers

    private static func highPass(_ input: [Double], amount: Double) -> [Double] {
        zip(input, lowPass(input, amount: amount)).map { $0 - $1 }
    }

    private static func grainSeed(material: MaterialID, index: Int) -> UInt64 {
        let materialIndex = UInt64(MaterialID.allCases.firstIndex(of: material) ?? 0)
        // Offset from the click and key seeds, which use the lower bits.
        return 1 << 40 | materialIndex << 8 | UInt64(index)
    }
}
