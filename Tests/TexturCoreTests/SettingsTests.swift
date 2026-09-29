import Foundation
import Testing
@testable import TexturCore

@Suite("Settings")
struct SettingsTests {
    @Test func defaultsAreComfortable() {
        let settings = Settings.default
        #expect(settings.isEnabled)
        #expect(settings.material == .linen)
        #expect(settings.pointerEnabled && settings.scrollEnabled && settings.tapEnabled)
        #expect(settings.strength == .strong)
        #expect(settings.grainScale == 1)
        #expect(!settings.clickSoundEnabled)
        #expect(!settings.keyboardSoundEnabled)
        #expect(!settings.textureSoundEnabled)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = Settings.default
            .updating(\.material, to: .gravel)
            .updating(\.strength, to: .light)
            .updating(\.volume, to: 0.3)
            .updating(\.keyboardSoundEnabled, to: true)
            .updating(\.textureSoundEnabled, to: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == original)
    }

    @Test func missingKeysKeepTheirDefaults() throws {
        let json = Data(#"{"material":"sand","volume":0.2}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.material == .sand)
        #expect(decoded.volume == 0.2)
        #expect(decoded.tapEnabled == Settings.default.tapEnabled)
        #expect(decoded.soundProfile == Settings.default.soundProfile)
        #expect(decoded.textureSoundEnabled == Settings.default.textureSoundEnabled)
    }

    @Test func settingsSavedBeforeADefaultChangedKeepTheirValue() throws {
        let json = Data(#"{"strength":"medium"}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.strength == .medium)
    }

    @Test func unknownValuesFallBackInsteadOfFailing() throws {
        let json = Data(#"{"material":"velvet","strength":"extreme","soundProfile":"theremin"}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.material == Settings.default.material)
        #expect(decoded.strength == Settings.default.strength)
        #expect(decoded.soundProfile == Settings.default.soundProfile)
    }

    @Test func outOfRangeNumbersAreClamped() throws {
        let json = Data(#"{"grainScale":12,"volume":-3}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.grainScale == Settings.grainScaleRange.upperBound)
        #expect(decoded.volume == 0)
        #expect(Settings.default.updating(\.volume, to: 4).volume == 1)
    }

    @Test func updatingReturnsACopy() {
        let original = Settings.default
        let changed = original.updating(\.material, to: .knurl)
        #expect(original.material == .linen)
        #expect(changed.material == .knurl)
    }
}
