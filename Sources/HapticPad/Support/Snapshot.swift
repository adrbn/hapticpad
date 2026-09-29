import AppKit
import SwiftUI

/// `HapticPad --snapshot <folder>`: renders the README hero, the panel under its
/// menu bar icon, as `hero-light.png` and `hero-dark.png`.
@MainActor
enum Snapshot {
    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else {
            print("Usage: HapticPad --snapshot <folder>")
            return 2
        }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel(store: .ephemeral)
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (name, appearanceName) in appearances {
            let url = folder.appendingPathComponent("hero-\(name).png")
            guard let appearance = NSAppearance(named: appearanceName),
                  let panel = renderPanel(model: model, appearance: appearance),
                  let png = HeroImage.compose(panel: panel, appearance: appearance)
            else {
                print("Could not render \(name)")
                return 1
            }
            do {
                try png.write(to: url)
                print("Wrote \(url.path)")
            } catch {
                print("Could not write \(url.path): \(error.localizedDescription)")
                return 1
            }
        }
        return 0
    }

    /// Renders the panel in a key window, so controls show their active colours.
    private static func renderPanel(model: AppModel, appearance: NSAppearance) -> NSBitmapImageRep? {
        let content = MenuContent(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.controlActiveState, .key)
        let host = NSHostingView(rootView: content)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = KeyableWindow(
            contentRect: host.frame.offsetBy(dx: -10_000, dy: -10_000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        defer { window.orderOut(nil) }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}

/// A borderless window that draws as the key window, like the open menu bar panel,
/// even though a command-line snapshot can't activate the app.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
