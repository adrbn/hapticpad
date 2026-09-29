/// The four waveforms HapticPad plays, from faintest to strongest.
///
/// They map to waveforms built into the Force Touch trackpad firmware: 1 and 5 are
/// silent Gaussian bumps, 4 adds a light click, 6 is the firmest built-in tap.
public enum PulseStrength: Int, CaseIterable, Comparable, Sendable {
    case whisper
    case soft
    case firm
    case strong

    public var actuationID: Int32 {
        switch self {
        case .whisper: 1
        case .soft: 5
        case .firm: 4
        case .strong: 6
        }
    }

    public func shifted(by offset: Int) -> PulseStrength {
        let index = min(max(rawValue + offset, 0), PulseStrength.allCases.count - 1)
        return PulseStrength(rawValue: index) ?? self
    }

    public static func < (lhs: PulseStrength, rhs: PulseStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One actuator hit, `delay` seconds after the start of its grain.
public struct Pulse: Equatable, Sendable {
    public let strength: PulseStrength
    public let delay: Double

    public init(strength: PulseStrength, delay: Double = 0) {
        self.strength = strength
        self.delay = delay
    }

    public func shifted(by offset: Int) -> Pulse {
        Pulse(strength: strength.shifted(by: offset), delay: delay)
    }

    public func delayed(by extra: Double) -> Pulse {
        Pulse(strength: strength, delay: delay + extra)
    }
}

/// The user-facing strength setting.
public enum HapticStrength: String, CaseIterable, Codable, Sendable {
    case subtle
    case light
    case medium
    case strong

    /// How many `PulseStrength` steps every pulse moves.
    public var offset: Int {
        switch self {
        case .subtle: -2
        case .light: -1
        case .medium: 0
        case .strong: 1
        }
    }

    public var label: String {
        switch self {
        case .subtle: "Subtle"
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }
}
