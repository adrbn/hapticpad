import Testing
@testable import TexturCore

private let sampleRate = 48_000.0

@Suite("Grain sounds")
struct GrainSoundTests {
    @Test(arguments: MaterialID.allCases)
    func everyVariantIsShortCleanAudio(material: MaterialID) {
        #expect(SoundSynth.grainVariantCount >= 3)
        for variant in 0..<SoundSynth.grainVariantCount {
            let samples = SoundSynth.renderGrain(material: material, variant: variant, sampleRate: sampleRate)
            #expect(samples.count > Int(sampleRate * 0.01), "\(material) \(variant) too short")
            #expect(samples.count < Int(sampleRate * 0.08), "\(material) \(variant) too long to follow a moving finger")
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
            #expect(abs(samples.first ?? 1) < 0.05, "\(material) \(variant) starts with a pop")
            #expect(abs(samples.last ?? 1) < 0.01, "\(material) \(variant) ends with a pop")
            #expect((samples.map(abs).max() ?? 0) > 0.05, "\(material) \(variant) is silent")
        }
    }

    @Test func renderingIsDeterministic() {
        let first = SoundSynth.renderGrain(material: .gravel, variant: 1, sampleRate: sampleRate)
        let second = SoundSynth.renderGrain(material: .gravel, variant: 1, sampleRate: sampleRate)
        #expect(first == second)
    }

    @Test func materialsAndVariantsSoundDifferent() {
        let materials = MaterialID.allCases.map { SoundSynth.renderGrain(material: $0, variant: 0, sampleRate: sampleRate) }
        #expect(Set(materials.map { $0.map(\.bitPattern) }).count == MaterialID.allCases.count)
        let variants = (0..<SoundSynth.grainVariantCount).map {
            SoundSynth.renderGrain(material: .wood, variant: $0, sampleRate: sampleRate)
        }
        #expect(Set(variants.map { $0.map(\.bitPattern) }).count == SoundSynth.grainVariantCount)
    }

    @Test func variantsOutsideTheRangeWrapAround() {
        let wrapped = SoundSynth.renderGrain(material: .knurl, variant: SoundSynth.grainVariantCount + 2, sampleRate: sampleRate)
        let direct = SoundSynth.renderGrain(material: .knurl, variant: 2, sampleRate: sampleRate)
        #expect(wrapped == direct)
    }

    @Test func strongerGrainsPlayLouder() {
        let levels = PulseStrength.allCases.map(SoundSynth.grainLevel(for:))
        #expect(levels == levels.sorted())
        #expect(Set(levels).count == levels.count)
        #expect(levels.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    @Test func aGrainSoundsAsLoudAsItsStrongestPulse() {
        let grain = [Pulse(strength: .soft), Pulse(strength: .firm, delay: 0.01), Pulse(strength: .whisper, delay: 0.02)]
        #expect(grain.peakStrength == .firm)
        #expect([Pulse]().peakStrength == nil)
    }
}
