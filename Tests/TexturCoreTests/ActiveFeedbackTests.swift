import Testing
@testable import TexturCore

@Suite("ActiveFeedback")
struct ActiveFeedbackTests {
    @Test func defaultsOnlyRunTheTouchStream() {
        let active = ActiveFeedback(settings: .default, hapticsReady: true)
        #expect(active.touches)
        #expect(!active.clickSounds && !active.keySounds && !active.grainSounds)
        #expect(!active.audio)
    }

    @Test func textureSoundWorksWithEveryTouchInputOff() {
        let settings = Settings.default
            .updating(\.pointerEnabled, to: false)
            .updating(\.scrollEnabled, to: false)
            .updating(\.tapEnabled, to: false)
            .updating(\.textureSoundEnabled, to: true)
        let active = ActiveFeedback(settings: settings, hapticsReady: true)
        #expect(!active.touches)
        #expect(active.grainSounds)
        #expect(active.audio)
    }

    @Test func withoutAHapticTrackpadOnlyClickAndKeySoundsRun() {
        let settings = Settings.default
            .updating(\.clickSoundEnabled, to: true)
            .updating(\.keyboardSoundEnabled, to: true)
            .updating(\.textureSoundEnabled, to: true)
        let active = ActiveFeedback(settings: settings, hapticsReady: false)
        #expect(!active.touches && !active.grainSounds)
        #expect(active.clickSounds && active.keySounds)
        #expect(active.audio)
    }

    @Test func switchingTexturOffStopsEverything() {
        let settings = Settings.default
            .updating(\.isEnabled, to: false)
            .updating(\.clickSoundEnabled, to: true)
            .updating(\.textureSoundEnabled, to: true)
        let active = ActiveFeedback(settings: settings, hapticsReady: true)
        #expect(!active.touches && !active.audio)
        #expect(!active.any)
    }
}
