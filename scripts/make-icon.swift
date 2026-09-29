// Draws the app icon and writes an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let scale = size / 1024
        let canvas = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let squircle = NSBezierPath(roundedRect: canvas, xRadius: 185 * scale, yRadius: 185 * scale)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.10, alpha: 1),
        ])?.draw(in: squircle, angle: -90)

        // The trackpad.
        let pad = canvas.insetBy(dx: 150 * scale, dy: 205 * scale)
        let padPath = NSBezierPath(roundedRect: pad, xRadius: 46 * scale, yRadius: 46 * scale)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.62, green: 0.65, blue: 0.74, alpha: 1),
        ])?.draw(in: padPath, angle: -90)

        // Ripples of grains spreading from a fingertip.
        let finger = NSPoint(x: pad.midX + 40 * scale, y: pad.midY - 10 * scale)
        NSGraphicsContext.saveGraphicsState()
        padPath.addClip()
        for ring in 1...5 {
            let radius = CGFloat(ring) * 44 * scale
            let dots = 10 + ring * 7
            for index in 0..<dots {
                let angle = CGFloat(index) / CGFloat(dots) * 2 * .pi + CGFloat(ring) * 0.3
                let point = NSPoint(x: finger.x + cos(angle) * radius, y: finger.y + sin(angle) * radius)
                let dotSize = (12 - CGFloat(ring) * 1.5) * scale
                let alpha = 0.75 - CGFloat(ring) * 0.12
                NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.40, alpha: alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let tip = NSRect(x: finger.x - 34 * scale, y: finger.y - 34 * scale, width: 68 * scale, height: 68 * scale)
        NSColor(calibratedRed: 0.53, green: 0.62, blue: 1.0, alpha: 1).setFill()
        NSBezierPath(ovalIn: tip).fill()
        return true
    }
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let image = drawIcon(size: pixels)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { fatalError("Could not render \(name)") }
    try png.write(to: output.appendingPathComponent("\(name).png"))
}
print("Wrote \(output.path)")
