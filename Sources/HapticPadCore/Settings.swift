/// Everything the user can change, persisted as JSON.
///
/// Decoding is forgiving: missing keys keep their defaults, unknown enum values
/// fall back, and numbers are clamped, so an old or hand-edited file never
/// resets the whole configuration.
public struct Settings: Codable, Equatable, Sendable {
    public static let grainScaleRange: ClosedRange<Double> = 0.5...2.0
    public static let volumeRange: ClosedRange<Double> = 0.0...1.0
    public static let `default` = Settings()

    public var isEnabled = true
    public var material = MaterialID.fallback
    public var pointerEnabled = true
    public var scrollEnabled = true
    public var tapEnabled = true
    public var strength = HapticStrength.medium
    public var grainScale = 1.0
    public var soundProfile = SoundProfileID.fallback
    public var clickSoundEnabled = false
    public var keyboardSoundEnabled = false
    public var volume = 0.5

    public init() {}

    /// Returns a copy with one value changed and every number kept in range.
    public func updating<Value>(_ keyPath: WritableKeyPath<Settings, Value>, to value: Value) -> Settings {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy.clamped()
    }

    private func clamped() -> Settings {
        var copy = self
        copy.grainScale = Self.clamp(grainScale, to: Self.grainScaleRange)
        copy.volume = Self.clamp(volume, to: Self.volumeRange)
        return copy
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, material, pointerEnabled, scrollEnabled, tapEnabled, strength, grainScale
        case soundProfile, clickSoundEnabled, keyboardSoundEnabled, volume
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = Settings()
        var decoded = base
        decoded.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? base.isEnabled
        decoded.material = try container.decodeIfPresent(String.self, forKey: .material)
            .map(MaterialID.init(storedValue:)) ?? base.material
        decoded.pointerEnabled = try container.decodeIfPresent(Bool.self, forKey: .pointerEnabled) ?? base.pointerEnabled
        decoded.scrollEnabled = try container.decodeIfPresent(Bool.self, forKey: .scrollEnabled) ?? base.scrollEnabled
        decoded.tapEnabled = try container.decodeIfPresent(Bool.self, forKey: .tapEnabled) ?? base.tapEnabled
        decoded.strength = try container.decodeIfPresent(String.self, forKey: .strength)
            .flatMap(HapticStrength.init(rawValue:)) ?? base.strength
        decoded.grainScale = try container.decodeIfPresent(Double.self, forKey: .grainScale) ?? base.grainScale
        decoded.soundProfile = try container.decodeIfPresent(String.self, forKey: .soundProfile)
            .map(SoundProfileID.init(storedValue:)) ?? base.soundProfile
        decoded.clickSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .clickSoundEnabled) ?? base.clickSoundEnabled
        decoded.keyboardSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .keyboardSoundEnabled)
            ?? base.keyboardSoundEnabled
        decoded.volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? base.volume
        self = decoded.clamped()
    }
}
