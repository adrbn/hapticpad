/// The six built-in surfaces.
public enum MaterialCatalog {
    public static let all: [Material] = MaterialID.allCases.map(material(for:))

    public static func material(for id: MaterialID) -> Material {
        switch id {
        case .linen:
            Material(
                id: .linen, name: "Linen", summary: "Fine, even weave",
                spacing: 0.8, jitter: 0.12, axisWeights: Vector2(x: 1, y: 1),
                grain: [Pulse(strength: .whisper)],
                accent: .init(every: 5, chance: 0, grain: [Pulse(strength: .soft)]),
                skipChance: 0
            )
        case .corduroy:
            Material(
                id: .corduroy, name: "Corduroy", summary: "Vertical ridges, felt when moving sideways",
                spacing: 2.4, jitter: 0.03, axisWeights: Vector2(x: 1, y: 0.08),
                grain: [Pulse(strength: .soft)],
                accent: nil,
                skipChance: 0
            )
        case .sand:
            Material(
                id: .sand, name: "Sand", summary: "Dense, random fine grain",
                spacing: 0.5, jitter: 0.9, axisWeights: Vector2(x: 1, y: 1),
                grain: [Pulse(strength: .whisper)],
                accent: .init(every: 0, chance: 0.06, grain: [Pulse(strength: .soft)]),
                skipChance: 0.3
            )
        case .wood:
            Material(
                id: .wood, name: "Wood", summary: "Grain lines with the odd knot",
                spacing: 1.7, jitter: 0.45, axisWeights: Vector2(x: 0.3, y: 1),
                grain: [Pulse(strength: .whisper)],
                accent: .init(every: 0, chance: 0.05, grain: [Pulse(strength: .firm), Pulse(strength: .whisper, delay: 0.012)]),
                skipChance: 0
            )
        case .gravel:
            Material(
                id: .gravel, name: "Gravel", summary: "Sparse, rounded stones",
                spacing: 5.5, jitter: 0.55, axisWeights: Vector2(x: 1, y: 1),
                grain: [Pulse(strength: .soft), Pulse(strength: .whisper, delay: 0.014)],
                accent: .init(every: 0, chance: 0.25, grain: [Pulse(strength: .firm), Pulse(strength: .soft, delay: 0.016)]),
                skipChance: 0.1
            )
        case .knurl:
            Material(
                id: .knurl, name: "Knurl", summary: "Crisp machined diamond grid",
                spacing: 1.2, jitter: 0, axisWeights: Vector2(x: 1, y: 1),
                grain: [Pulse(strength: .soft)],
                accent: .init(every: 4, chance: 0, grain: [Pulse(strength: .firm)]),
                skipChance: 0
            )
        }
    }
}
