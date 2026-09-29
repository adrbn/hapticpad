import AppKit

/// Draws the README hero: a slice of menu bar with the HapticPad icon selected,
/// and the panel floating below it with rounded corners and a soft shadow.
@MainActor
enum HeroImage {
    private static let scale: CGFloat = 2
    private static let margin: CGFloat = 44
    private static let barInset: CGFloat = 16
    private static let barHeight: CGFloat = 26
    private static let barGap: CGFloat = 8
    private static let bottomMargin: CGFloat = 60
    private static let panelRadius: CGFloat = 12

    static func compose(panel: NSBitmapImageRep, appearance: NSAppearance) -> Data? {
        let panelSize = panel.size
        let canvas = CGSize(
            width: panelSize.width + margin * 2,
            height: barInset + barHeight + barGap + panelSize.height + bottomMargin
        )
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.width * scale),
            pixelsHigh: Int(canvas.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = canvas

        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Draw top-down, in points.
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: canvas.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

        appearance.performAsCurrentDrawingAppearance {
            let panelRect = CGRect(origin: CGPoint(x: margin, y: barInset + barHeight + barGap), size: panelSize)
            drawMenuBar(width: canvas.width, iconCenterX: panelRect.minX + panelSize.width * 0.62, isDark: isDark)
            drawPanel(panel, in: panelRect, context: cg, isDark: isDark)
        }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Menu bar

    private static func drawMenuBar(width: CGFloat, iconCenterX: CGFloat, isDark: Bool) {
        let bar = CGRect(x: barInset, y: barInset, width: width - barInset * 2, height: barHeight)
        let shape = NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8)
        (isDark ? NSColor(white: 0.16, alpha: 0.94) : NSColor(white: 1, alpha: 0.82)).setFill()
        shape.fill()
        (isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.08)).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        let ink = isDark ? NSColor(white: 1, alpha: 0.9) : NSColor(white: 0, alpha: 0.82)
        let pill = CGRect(x: iconCenterX - 15, y: bar.midY - 11, width: 30, height: 22)
        (isDark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.09)).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        drawSymbol("hand.point.up.left.fill", centeredAt: CGPoint(x: pill.midX, y: pill.midY), color: ink)

        var x = pill.maxX + 14
        for symbol in ["battery.100percent", "wifi"] {
            let width = drawSymbol(symbol, leadingAt: CGPoint(x: x, y: bar.midY), color: ink)
            x += width + 14
        }
        let clock = NSAttributedString(string: "Mon 9:41", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: ink,
        ])
        clock.draw(at: CGPoint(x: x, y: bar.midY - clock.size().height / 2))
    }

    @discardableResult
    private static func drawSymbol(_ name: String, centeredAt center: CGPoint, color: NSColor) -> CGFloat {
        guard let image = symbol(name, color: color) else { return 0 }
        let origin = CGPoint(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2)
        image.draw(in: CGRect(origin: origin, size: image.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        return image.size.width
    }

    private static func drawSymbol(_ name: String, leadingAt point: CGPoint, color: NSColor) -> CGFloat {
        guard let image = symbol(name, color: color) else { return 0 }
        return drawSymbol(name, centeredAt: CGPoint(x: point.x + image.size.width / 2, y: point.y), color: color)
    }

    private static func symbol(_ name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    // MARK: - Panel

    private static func drawPanel(_ panel: NSBitmapImageRep, in rect: CGRect, context: CGContext, isDark: Bool) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: panelRadius, yRadius: panelRadius)
        context.saveGState()
        // Shadow offsets live in device space, where y points up.
        context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 40 * scale,
                          color: NSColor(white: 0, alpha: isDark ? 0.55 : 0.22).cgColor)
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        context.restoreGState()

        context.saveGState()
        shape.addClip()
        panel.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGState()

        (isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.12)).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}
