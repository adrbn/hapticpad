import Foundation
import TexturCore
import SwiftUI

/// The panel shown from the menu bar icon.
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            StatusLine(model: model)
            Divider()
            MaterialSection(model: model)
            FeelSection(model: model)
            SoundSection(model: model)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear(perform: model.refresh)
    }

    private var header: some View {
        HStack {
            Text("Textur")
                .font(.headline)
            Spacer()
            Toggle("Enabled", isOn: model.binding(\.isEnabled))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Textur enabled")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .font(.callout)
        }
    }
}

/// Whether haptics can play on this Mac, in one line.
private struct StatusLine: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: model.hapticsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.hapticsReady ? .green : .orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !model.hapticsReady {
                Button("Rescan", action: model.restartHardware)
                    .controlSize(.small)
            }
        }
    }

    private var message: String {
        if !model.isFrameworkAvailable {
            return "This macOS version doesn't expose the trackpad actuator. Sounds still work."
        }
        guard let trackpad = model.trackpads.first else {
            return "No Force Touch trackpad found. Sounds still work."
        }
        let size = "\(Int(trackpad.surface.width.rounded())) × \(Int(trackpad.surface.height.rounded())) mm"
        let extra = model.trackpads.count > 1 ? " + \(model.trackpads.count - 1) more" : ""
        return "\(trackpad.label), \(size)\(extra)"
    }
}

private struct MaterialSection: View {
    let model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Material")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MaterialCatalog.all) { material in
                    MaterialTile(material: material, isSelected: material.id == model.settings.material) {
                        model.selectMaterial(material.id)
                    }
                }
            }
            Text(model.material.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MaterialTile: View {
    let material: TexturCore.Material
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                MaterialSwatch(id: material.id)
                    .frame(height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                    }
                Text(material.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(material.name), \(material.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FeelSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Feel")
            FieldRow("Strength") {
                Picker("Strength", selection: model.binding(\.strength)) {
                    ForEach(HapticStrength.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            FieldRow("Grain") {
                HStack(spacing: 6) {
                    Text("Fine").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: grainPosition, in: -1...1) { editing in
                        if !editing { model.previewMaterial() }
                    }
                    .labelsHidden()
                    Text("Coarse").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                Toggle("Pointer", isOn: model.binding(\.pointerEnabled))
                    .help("Texture under one finger moving the pointer")
                Toggle("Scroll", isOn: model.binding(\.scrollEnabled))
                    .help("Texture under two fingers scrolling")
                Toggle("Tap", isOn: model.binding(\.tapEnabled))
                    .help("A light tick each time a finger lands, so taps can be felt")
            }
            .toggleStyle(.checkbox)
        }
        .font(.callout)
        .disabled(!model.hapticsReady)
        .opacity(model.hapticsReady ? 1 : 0.5)
    }

    /// Grain size on a log scale, so the default (1x) sits in the middle of the slider.
    private var grainPosition: Binding<Double> {
        Binding(
            get: { log2(model.settings.grainScale) },
            set: { model.update(\.grainScale, to: pow(2, $0)) }
        )
    }
}

private struct SoundSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Sound")
            FieldRow("Profile") {
                Picker("Profile", selection: Binding(
                    get: { model.settings.soundProfile },
                    set: { profile in
                        model.update(\.soundProfile, to: profile)
                        model.previewSound()
                    }
                )) {
                    ForEach(SoundProfileID.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 14) {
                Toggle("Clicks", isOn: model.binding(\.clickSoundEnabled))
                Toggle("Keyboard", isOn: model.binding(\.keyboardSoundEnabled))
            }
            .toggleStyle(.checkbox)
            if model.keyboardNeedsPermission {
                PermissionHint(action: model.openInputMonitoringSettings)
            }
            FieldRow("Volume") {
                Slider(value: model.binding(\.volume), in: TexturCore.Settings.volumeRange) { editing in
                    if !editing { model.previewSound() }
                }
                .labelsHidden()
            }
        }
        .font(.callout)
    }
}

private struct PermissionHint: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard sounds need Input Monitoring. Textur only checks which kind of key was pressed, never what you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Input Monitoring settings", action: action)
                .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A label and control on one line, with labels aligned across sections.
private struct FieldRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 62, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

extension AppModel {
    /// A SwiftUI binding that writes through `update`, keeping settings immutable.
    func binding<Value>(_ keyPath: WritableKeyPath<TexturCore.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { self.update(keyPath, to: $0) })
    }
}
