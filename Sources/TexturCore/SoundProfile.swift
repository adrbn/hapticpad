/// The built-in sound families.
public enum SoundProfileID: String, CaseIterable, Codable, Sendable, Identifiable {
    case kalimba
    case muted
    case mechanical
    case droplet

    public static let fallback: SoundProfileID = .kalimba

    public var id: String { rawValue }

    public init(storedValue: String) {
        self = SoundProfileID(rawValue: storedValue) ?? .fallback
    }

    public var label: String {
        switch self {
        case .kalimba: "Kalimba"
        case .muted: "Muted"
        case .mechanical: "Mechanical"
        case .droplet: "Droplet"
        }
    }

    /// Melodic profiles walk through notes instead of picking random variants.
    public var isMelodic: Bool { self == .kalimba }
}

/// What produced a sound. Only the key family is ever looked at, never which key.
public enum SoundTrigger: CaseIterable, Sendable, Hashable {
    case click
    case key
    case spaceKey
    case returnKey
    case deleteKey

    /// Classifies a macOS virtual key code into a family.
    public init(keyCode: Int64) {
        switch keyCode {
        case 49: self = .spaceKey
        case 36, 76: self = .returnKey
        case 51, 117: self = .deleteKey
        default: self = .key
        }
    }
}

/// A gentle random walk through a scale, so repeated clicks form a melody.
public struct MelodyWalker: Sendable, Equatable {
    public let noteCount: Int
    public let current: Int
    private let random: SeededRandom

    public init(noteCount: Int, seed: UInt64) {
        self.init(noteCount: max(noteCount, 1), current: max(noteCount, 1) / 2, random: SeededRandom(seed: seed))
    }

    private init(noteCount: Int, current: Int, random: SeededRandom) {
        self.noteCount = noteCount
        self.current = current
        self.random = random
    }

    public func next() -> (MelodyWalker, Int) {
        guard noteCount > 1 else { return (self, 0) }
        let (nextRandom, bits) = random.nextBits()
        let steps = [-2, -1, 1, 2]
        let step = steps[Int(bits % UInt64(steps.count))]
        let forward = current + step
        let reflected = (0..<noteCount).contains(forward) ? forward : current - step
        let note = min(max(reflected, 0), noteCount - 1)
        return (MelodyWalker(noteCount: noteCount, current: note, random: nextRandom), note)
    }
}
