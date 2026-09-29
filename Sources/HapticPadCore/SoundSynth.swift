import Foundation

/// Renders every HapticPad sound from scratch, so the app ships no audio files.
///
/// All functions are pure and deterministic: the same profile, trigger and
/// variant always produce the same samples.
public enum SoundSynth {
    /// C major pentatonic over two octaves, in semitones above C5.
    static let pentatonic = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
    static let fadeInSeconds = 0.0005
    static let fadeOutSeconds = 0.006

    public static func variantCount(profile: SoundProfileID, trigger: SoundTrigger) -> Int {
        switch (profile, trigger) {
        case (.kalimba, _): pentatonic.count
        case (_, .click), (_, .key): 6
        default: 3
        }
    }

    public static func render(profile: SoundProfileID, trigger: SoundTrigger, variant: Int, sampleRate: Double) -> [Float] {
        let count = variantCount(profile: profile, trigger: trigger)
        let index = ((variant % count) + count) % count
        // Spread variants evenly over -1...1 so neighbours sound related but distinct.
        let variation = count > 1 ? Double(index) / Double(count - 1) * 2 - 1 : 0
        let seed = seed(profile: profile, trigger: trigger, index: index)
        let (samples, gain): ([Double], Double) = switch profile {
        case .kalimba: kalimba(trigger: trigger, note: index, sampleRate: sampleRate)
        case .muted: muted(trigger: trigger, variation: variation, seed: seed, sampleRate: sampleRate)
        case .mechanical: mechanical(trigger: trigger, variation: variation, seed: seed, sampleRate: sampleRate)
        case .droplet: droplet(trigger: trigger, variation: variation, sampleRate: sampleRate)
        }
        return finish(samples, gain: gain, sampleRate: sampleRate)
    }

    // MARK: - Profiles

    private static func kalimba(trigger: SoundTrigger, note: Int, sampleRate: Double) -> ([Double], Double) {
        let octave = [.spaceKey, .returnKey].contains(trigger) ? -12 : 0
        let frequency = 523.25 * pow(2, Double(pentatonic[note] + octave) / 12)
        let (duration, decay, gain): (Double, Double, Double) = switch trigger {
        case .click: (0.45, 0.16, 0.8)
        case .spaceKey, .returnKey: (0.35, 0.11, 0.65)
        case .key, .deleteKey: (0.25, 0.07, 0.55)
        }
        let samples = timeline(duration: duration, sampleRate: sampleRate).map { t in
            let body = sin(2 * .pi * frequency * t) + 0.12 * sin(4 * .pi * frequency * t)
            let tine = 0.35 * sin(2 * .pi * frequency * 5.4 * t) * exp(-t / 0.015)
            return (body + tine) * exp(-t / decay)
        }
        return (samples, gain)
    }

    private static func muted(trigger: SoundTrigger, variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let (base, decay, duration): (Double, Double, Double) = switch trigger {
        case .click: (200, 0.018, 0.10)
        case .key: (170, 0.020, 0.10)
        case .deleteKey: (150, 0.022, 0.10)
        case .spaceKey, .returnKey: (115, 0.035, 0.14)
        }
        let fundamental = base * (1 + 0.08 * variation)
        let times = timeline(duration: duration, sampleRate: sampleRate)
        let thump = integratedSine(times: times, sampleRate: sampleRate) { t in
            fundamental * (0.7 + 0.3 * exp(-t / 0.01))
        }
        let dust = lowPass(noise(count: times.count, seed: seed), amount: 0.12)
        let samples = zip(times, zip(thump, dust)).map { t, parts in
            parts.0 * exp(-t / decay) + 0.5 * parts.1 * exp(-t / 0.004)
        }
        return (samples, 0.7)
    }

    private static func mechanical(trigger: SoundTrigger, variation: Double, seed: UInt64, sampleRate: Double) -> ([Double], Double) {
        let (ping, thud): (Double, Double?) = switch trigger {
        case .click: (4200, nil)
        case .key: (3000, 230)
        case .deleteKey: (2800, 210)
        case .returnKey: (2500, 170)
        case .spaceKey: (2200, 150)
        }
        let long = [.spaceKey, .returnKey].contains(trigger)
        let times = timeline(duration: long ? 0.11 : 0.08, sampleRate: sampleRate)
        let raw = noise(count: times.count, seed: seed)
        let crisp = zip(raw, lowPass(raw, amount: 0.3)).map { $0 - $1 }
        let pingFrequency = ping * (1 + 0.06 * variation)
        let samples = zip(times, crisp).map { t, hiss in
            let click = hiss * exp(-t / 0.0012) + 0.45 * sin(2 * .pi * pingFrequency * t) * exp(-t / 0.005)
            let bottom = thud.map { delayedTone(frequency: $0, at: t, start: 0.009, decay: 0.012, level: 0.6) } ?? 0
            let rattle = trigger == .spaceKey ? 0.25 * hiss * delayedEnvelope(at: t, start: 0.03, decay: 0.001) : 0
            return click + bottom + rattle
        }
        return (samples, 0.75)
    }

    private static func droplet(trigger: SoundTrigger, variation: Double, sampleRate: Double) -> ([Double], Double) {
        let (base, decay): (Double, Double) = switch trigger {
        case .click: (520, 0.035)
        case .key: (700, 0.022)
        case .deleteKey: (600, 0.022)
        case .spaceKey, .returnKey: (330, 0.045)
        }
        let start = base * (1 + 0.25 * variation)
        let times = timeline(duration: 0.14, sampleRate: sampleRate)
        let tone = integratedSine(times: times, sampleRate: sampleRate) { t in
            start * (1 + 1.3 * (1 - exp(-t / 0.012)))
        }
        return (zip(times, tone).map { t, value in value * exp(-t / decay) }, 0.7)
    }

    // MARK: - Building blocks

    private static func timeline(duration: Double, sampleRate: Double) -> [Double] {
        (0..<max(Int(duration * sampleRate), 2)).map { Double($0) / sampleRate }
    }

    /// A sine whose frequency changes over time, integrated so the phase stays continuous.
    private static func integratedSine(times: [Double], sampleRate: Double, frequency: (Double) -> Double) -> [Double] {
        var phase = 0.0
        return times.map { t in
            let value = sin(phase)
            phase += 2 * .pi * frequency(t) / sampleRate
            return value
        }
    }

    private static func delayedTone(frequency: Double, at t: Double, start: Double, decay: Double, level: Double) -> Double {
        guard t >= start else { return 0 }
        let local = t - start
        return level * sin(2 * .pi * frequency * local) * exp(-local / decay)
    }

    private static func delayedEnvelope(at t: Double, start: Double, decay: Double) -> Double {
        t >= start ? exp(-(t - start) / decay) : 0
    }

    private static func noise(count: Int, seed: UInt64) -> [Double] {
        var generator = SeededRandom(seed: seed)
        return (0..<count).map { _ in
            let (next, value) = generator.nextSigned()
            generator = next
            return value
        }
    }

    private static func lowPass(_ input: [Double], amount: Double) -> [Double] {
        var state = 0.0
        return input.map { sample in
            state += amount * (sample - state)
            return state
        }
    }

    /// Fades both ends to silence and normalizes the peak to `gain`.
    private static func finish(_ samples: [Double], gain: Double, sampleRate: Double) -> [Float] {
        let count = samples.count
        let fadeIn = max(Int(fadeInSeconds * sampleRate), 1)
        let fadeOut = max(Int(fadeOutSeconds * sampleRate), 1)
        let faded = samples.enumerated().map { index, value in
            let rise = min(Double(index) / Double(fadeIn), 1)
            let fall = min(Double(count - 1 - index) / Double(fadeOut), 1)
            return value * rise * fall
        }
        let peak = faded.map(abs).max() ?? 0
        let scale = peak > 0 ? gain / peak : 0
        return faded.map { Float($0 * scale) }
    }

    private static func seed(profile: SoundProfileID, trigger: SoundTrigger, index: Int) -> UInt64 {
        let profileIndex = UInt64(SoundProfileID.allCases.firstIndex(of: profile) ?? 0)
        let triggerIndex = UInt64(SoundTrigger.allCases.firstIndex(of: trigger) ?? 0)
        return profileIndex << 16 | triggerIndex << 8 | UInt64(index)
    }
}
