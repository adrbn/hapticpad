/// Stable identifiers for the built-in materials, persisted in settings.
public enum MaterialID: String, CaseIterable, Codable, Sendable, Identifiable {
    case linen
    case corduroy
    case sand
    case wood
    case gravel
    case knurl

    public static let fallback: MaterialID = .linen

    public var id: String { rawValue }

    /// Reads a persisted value, falling back to the default for unknown names.
    public init(storedValue: String) {
        self = MaterialID(rawValue: storedValue) ?? .fallback
    }
}

/// A virtual surface: how far apart its grains are and how each grain feels.
public struct Material: Sendable, Equatable, Identifiable {
    /// A stronger grain mixed in periodically and/or at random.
    public struct Accent: Sendable, Equatable {
        /// Every n-th grain is accented (0 disables the period).
        public let every: Int
        /// Probability (0...1) that any other grain is accented.
        public let chance: Double
        public let grain: [Pulse]

        public init(every: Int, chance: Double, grain: [Pulse]) {
            self.every = every
            self.chance = chance
            self.grain = grain
        }
    }

    public let id: MaterialID
    public let name: String
    public let summary: String
    /// Mean distance between grains, in millimetres of finger travel.
    public let spacing: Double
    /// How irregular the spacing is, 0 (machined) to 1 (chaotic).
    public let jitter: Double
    /// Per-axis sensitivity. (1, 0) makes vertical ridges: only sideways travel is felt.
    public let axisWeights: Vector2
    /// The pulses played for an ordinary grain.
    public let grain: [Pulse]
    public let accent: Accent?
    /// Probability (0..<1) that a grain is left out, for sparse surfaces.
    public let skipChance: Double

    public init(
        id: MaterialID,
        name: String,
        summary: String,
        spacing: Double,
        jitter: Double,
        axisWeights: Vector2,
        grain: [Pulse],
        accent: Accent?,
        skipChance: Double
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.spacing = spacing
        self.jitter = jitter
        self.axisWeights = axisWeights
        self.grain = grain
        self.accent = accent
        self.skipChance = skipChance
    }

    /// What a tap on this surface feels like.
    public func tapGrain(strength: HapticStrength) -> [Pulse] {
        (accent?.grain ?? grain).map { $0.shifted(by: strength.offset) }
    }

    /// A short phrase of grains that lets someone feel the material right after choosing it.
    public func preview(strength: HapticStrength, grains: Int = 8) -> [Pulse] {
        previewGrains(strength: strength, grains: grains).flatMap { $0 }
    }

    /// The same phrase, one entry per grain, so each grain can also be heard once.
    public func previewGrains(strength: HapticStrength, grains: Int = 8) -> [[Pulse]] {
        let interval = min(max(spacing * 0.03, 0.045), 0.12)
        return (0..<grains).map { index -> [Pulse] in
            let accented = accent.map { $0.every > 0 ? (index + 1) % $0.every == 0 : index == grains / 2 } ?? false
            let source = accented ? (accent?.grain ?? grain) : grain
            return source.map { $0.shifted(by: strength.offset).delayed(by: Double(index) * interval) }
        }
    }
}
