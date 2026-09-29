import HapticPadCore
import SwiftUI

/// A small procedural drawing of each material, so tiles read at a glance.
struct MaterialSwatch: View {
    let id: MaterialID
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(base))
            switch id {
            case .linen: drawLinen(in: context, size: size)
            case .corduroy: drawCorduroy(in: context, size: size)
            case .sand: drawSand(in: context, size: size)
            case .wood: drawWood(in: context, size: size)
            case .gravel: drawGravel(in: context, size: size)
            case .knurl: drawKnurl(in: context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private var isDark: Bool { colorScheme == .dark }

    private var hue: Double {
        switch id {
        case .linen: 0.11
        case .corduroy: 0.06
        case .sand: 0.12
        case .wood: 0.08
        case .gravel: 0.58
        case .knurl: 0.60
        }
    }

    private var saturation: Double {
        [.gravel, .knurl].contains(id) ? 0.08 : 0.32
    }

    private var base: Color {
        Color(hue: hue, saturation: saturation, brightness: isDark ? 0.34 : 0.86)
    }

    private var ink: Color {
        Color(hue: hue, saturation: saturation + 0.1, brightness: isDark ? 0.62 : 0.52)
    }

    private var highlight: Color {
        Color(hue: hue, saturation: saturation * 0.6, brightness: isDark ? 0.5 : 0.97)
    }

    // MARK: - Patterns

    private func drawLinen(in context: GraphicsContext, size: CGSize) {
        let step: CGFloat = 3
        for (index, x) in stride(from: 0, through: size.width, by: step).enumerated() {
            let line = Path { $0.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)) }
            context.fill(line, with: .color(ink.opacity(index.isMultiple(of: 2) ? 0.35 : 0.18)))
        }
        for (index, y) in stride(from: 0, through: size.height, by: step).enumerated() {
            let line = Path { $0.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)) }
            context.fill(line, with: .color(ink.opacity(index.isMultiple(of: 2) ? 0.18 : 0.32)))
        }
    }

    private func drawCorduroy(in context: GraphicsContext, size: CGSize) {
        let pitch: CGFloat = 6
        for x in stride(from: 0, through: size.width, by: pitch) {
            let ridge = Path(roundedRect: CGRect(x: x + 1, y: -2, width: pitch - 2.5, height: size.height + 4), cornerRadius: 2)
            context.fill(ridge, with: .color(highlight.opacity(0.7)))
            let groove = Path { $0.addRect(CGRect(x: x + pitch - 1.5, y: 0, width: 1.5, height: size.height)) }
            context.fill(groove, with: .color(ink.opacity(0.55)))
        }
    }

    private func drawSand(in context: GraphicsContext, size: CGSize) {
        var random = SeededRandom(seed: 11)
        for _ in 0..<420 {
            let (afterX, x) = random.nextUnit()
            let (afterY, y) = afterX.nextUnit()
            let (afterR, r) = afterY.nextUnit()
            random = afterR
            let radius = 0.35 + r * 0.6
            let dot = Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color((r > 0.5 ? ink : highlight).opacity(0.75)))
        }
    }

    private func drawWood(in context: GraphicsContext, size: CGSize) {
        let knot = CGPoint(x: size.width * 0.68, y: size.height * 0.52)
        for y in stride(from: CGFloat(-4), through: size.height + 4, by: 3.2) {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            for x in stride(from: CGFloat(0), through: size.width, by: 2) {
                let distance = hypot(x - knot.x, y - knot.y)
                let bulge = max(0, 9 - distance) * 0.9 * (y < knot.y ? -1 : 1)
                line.addLine(to: CGPoint(x: x, y: y + sin(x / 11 + y / 7) * 1.2 + bulge))
            }
            context.stroke(line, with: .color(ink.opacity(0.45)), lineWidth: 0.8)
        }
        let knotShape = Path(ellipseIn: CGRect(x: knot.x - 4, y: knot.y - 2.5, width: 8, height: 5))
        context.fill(knotShape, with: .color(ink.opacity(0.6)))
    }

    private func drawGravel(in context: GraphicsContext, size: CGSize) {
        var random = SeededRandom(seed: 5)
        for row in stride(from: CGFloat(-2), through: size.height, by: 8) {
            for column in stride(from: CGFloat(-2), through: size.width, by: 9) {
                let (afterA, a) = random.nextUnit()
                let (afterB, b) = afterA.nextUnit()
                random = afterB
                let width = 6 + a * 4
                let stone = CGRect(x: column + b * 3, y: row + a * 2, width: width, height: width * 0.8)
                context.fill(Path(ellipseIn: stone), with: .color(highlight.opacity(0.55 + b * 0.35)))
                context.stroke(Path(ellipseIn: stone), with: .color(ink.opacity(0.45)), lineWidth: 0.7)
            }
        }
    }

    private func drawKnurl(in context: GraphicsContext, size: CGSize) {
        let pitch: CGFloat = 5
        let span = size.width + size.height
        for offset in stride(from: -span, through: span, by: pitch) {
            var rising = Path()
            rising.move(to: CGPoint(x: offset, y: size.height))
            rising.addLine(to: CGPoint(x: offset + size.height, y: 0))
            context.stroke(rising, with: .color(ink.opacity(0.55)), lineWidth: 0.9)
            var falling = Path()
            falling.move(to: CGPoint(x: offset, y: 0))
            falling.addLine(to: CGPoint(x: offset + size.height, y: size.height))
            context.stroke(falling, with: .color(highlight.opacity(0.8)), lineWidth: 0.9)
        }
    }
}
