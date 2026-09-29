import Testing
@testable import TexturCore

private let sampleRate = 48_000.0

private func zeroCrossings(_ samples: [Float]) -> Int {
    zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
}

@Suite("SoundSynth")
struct SoundSynthTests {
    @Test(arguments: SoundProfileID.allCases)
    func everyVariantIsCleanAudio(profile: SoundProfileID) {
        for trigger in SoundTrigger.allCases {
            let count = SoundSynth.variantCount(profile: profile, trigger: trigger)
            #expect(count >= 1)
            for variant in 0..<count {
                let samples = SoundSynth.render(profile: profile, trigger: trigger, variant: variant, sampleRate: sampleRate)
                #expect(samples.count > Int(sampleRate * 0.02), "\(profile) \(trigger) \(variant) too short")
                #expect(samples.count < Int(sampleRate * 1.0), "\(profile) \(trigger) \(variant) too long")
                #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
                #expect(abs(samples.first ?? 1) < 0.05, "\(profile) \(trigger) \(variant) starts with a pop")
                #expect(abs(samples.last ?? 1) < 0.01, "\(profile) \(trigger) \(variant) ends with a pop")
                #expect((samples.map(abs).max() ?? 0) > 0.05, "\(profile) \(trigger) \(variant) is silent")
            }
        }
    }

    @Test func renderingIsDeterministic() {
        let first = SoundSynth.render(profile: .mechanical, trigger: .key, variant: 2, sampleRate: sampleRate)
        let second = SoundSynth.render(profile: .mechanical, trigger: .key, variant: 2, sampleRate: sampleRate)
        #expect(first == second)
    }

    @Test func kalimbaNotesRiseWithTheVariantIndex() {
        let count = SoundSynth.variantCount(profile: .kalimba, trigger: .click)
        let crossings = (0..<count).map {
            zeroCrossings(SoundSynth.render(profile: .kalimba, trigger: .click, variant: $0, sampleRate: sampleRate))
        }
        #expect(count >= 8)
        #expect(crossings == crossings.sorted())
    }

    @Test func variantsOutsideTheRangeWrapAround() {
        let count = SoundSynth.variantCount(profile: .droplet, trigger: .click)
        let wrapped = SoundSynth.render(profile: .droplet, trigger: .click, variant: count + 1, sampleRate: sampleRate)
        let direct = SoundSynth.render(profile: .droplet, trigger: .click, variant: 1, sampleRate: sampleRate)
        #expect(wrapped == direct)
    }
}

@Suite("SoundTrigger")
struct SoundTriggerTests {
    @Test func keyCodesMapToKeyFamilies() {
        #expect(SoundTrigger(keyCode: 49) == .spaceKey)
        #expect(SoundTrigger(keyCode: 36) == .returnKey)
        #expect(SoundTrigger(keyCode: 76) == .returnKey)
        #expect(SoundTrigger(keyCode: 51) == .deleteKey)
        #expect(SoundTrigger(keyCode: 117) == .deleteKey)
        #expect(SoundTrigger(keyCode: 0) == .key)
    }
}

@Suite("MelodyWalker")
struct MelodyWalkerTests {
    @Test func staysInRangeWithSmallSteps() {
        var walker = MelodyWalker(noteCount: 10, seed: 3)
        var previous = walker.current
        var visited = Set<Int>()
        for _ in 0..<500 {
            let (next, note) = walker.next()
            walker = next
            #expect((0..<10).contains(note))
            #expect(abs(note - previous) <= 2)
            previous = note
            visited.insert(note)
        }
        #expect(visited.count >= 8)
    }

    @Test func singleNoteRangeIsStable() {
        let (_, note) = MelodyWalker(noteCount: 1, seed: 1).next()
        #expect(note == 0)
    }
}
