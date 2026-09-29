import AppKit
import SwiftUI

struct TexturApp: App {
    @State private var model: AppModel

    init() {
        // Menu bar only, even when launched outside the app bundle during development.
        NSApplication.shared.setActivationPolicy(.accessory)
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.settings.isEnabled ? "hand.point.up.left.fill" : "hand.point.up.left")
                .accessibilityLabel("Textur")
        }
        .menuBarExtraStyle(.window)
    }
}
