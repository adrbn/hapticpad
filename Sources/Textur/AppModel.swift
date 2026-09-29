import AppKit
import TexturCore
import Observation

/// Owns every service and keeps them in line with the settings.
@MainActor
@Observable
final class AppModel {
    private(set) var settings: Settings
    private(set) var trackpads: [Trackpad] = []
    private(set) var isFrameworkAvailable = false
    private(set) var hasKeyboardPermission = KeyboardMonitor.hasPermission
    private(set) var launchesAtLogin = LaunchAtLogin.isEnabled
    private(set) var isKeyboardListening = false
    /// A user-facing message about the last thing that went wrong, if any.
    var problem: String?

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let actuators = HapticActuators()
    @ObservationIgnored private let pipeline: FeedbackPipeline
    @ObservationIgnored private let touchStream: TouchStream
    @ObservationIgnored private let sound = SoundPlayer()
    @ObservationIgnored private let clicks = ClickMonitor()
    @ObservationIgnored private let keys = KeyboardMonitor()
    @ObservationIgnored private let latency = LatencyActivity()
    @ObservationIgnored private var watcher: TrackpadWatcher?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// macOS shows the Input Monitoring prompt once; later requests only open the hint.
    @ObservationIgnored private var hasRequestedKeyboardPermission = false

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        settings = store.load()
        pipeline = FeedbackPipeline(actuators: actuators) { [sound] strength in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { sound.playGrain(strength) }
            }
        }
        touchStream = TouchStream(pipeline: pipeline)
        scanTrackpads()
        apply(settings)
        watcher = TrackpadWatcher { [weak self] in self?.refreshTrackpads() }
        watcher?.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartHardware() }
        }
    }

    var material: Material { MaterialCatalog.material(for: settings.material) }
    var hapticsReady: Bool { isFrameworkAvailable && !trackpads.isEmpty }
    var keyboardNeedsPermission: Bool { settings.isEnabled && settings.keyboardSoundEnabled && !isKeyboardListening }

    // MARK: - Actions

    func update<Value>(_ keyPath: WritableKeyPath<Settings, Value>, to value: Value) {
        settings = settings.updating(keyPath, to: value)
        store.save(settings)
        apply(settings)
    }

    func selectMaterial(_ id: MaterialID) {
        update(\.material, to: id)
        previewMaterial()
    }

    /// Plays a short phrase of the current material. Felt only while a finger rests on the trackpad,
    /// and heard too when texture sound is on.
    func previewMaterial() {
        guard hapticsReady else { return }
        let grains = material.previewGrains(strength: settings.strength)
        actuators.play(grains.flatMap { $0 }, on: trackpads)
        if ActiveFeedback(settings: settings, hapticsReady: hapticsReady).grainSounds {
            sound.playGrains(grains)
        }
    }

    func previewSound() {
        sound.play(.click)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            problem = nil
        } catch {
            problem = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchesAtLogin = LaunchAtLogin.isEnabled
    }

    /// Re-checks things the user may have changed meanwhile: System Settings and connected trackpads.
    func refresh() {
        hasKeyboardPermission = KeyboardMonitor.hasPermission
        launchesAtLogin = LaunchAtLogin.isEnabled
        if settings.isEnabled, settings.keyboardSoundEnabled, !keys.isRunning {
            startKeyboard(prompt: false)
        }
        refreshTrackpads()
    }

    func restartHardware() {
        touchStream.stop()
        actuators.reset()
        scanTrackpads()
        apply(settings)
    }

    func openInputMonitoringSettings() {
        KeyboardMonitor.openPrivacySettings()
    }

    // MARK: - Wiring

    /// Rebuilds the hardware only when a trackpad was connected or disconnected.
    private func refreshTrackpads() {
        if TrackpadDiscovery.trackpads() != trackpads {
            restartHardware()
        }
    }

    private func scanTrackpads() {
        isFrameworkAvailable = TrackpadDiscovery.isFrameworkAvailable
        trackpads = TrackpadDiscovery.trackpads()
        pipeline.update(trackpads: trackpads)
    }

    private func apply(_ settings: Settings) {
        pipeline.update(settings: settings)

        let active = ActiveFeedback(settings: settings, hapticsReady: hapticsReady)
        if active.touches, !touchStream.isRunning {
            touchStream.start()
        } else if !active.touches, touchStream.isRunning {
            touchStream.stop()
        }

        sound.load(profile: settings.soundProfile)
        sound.load(material: settings.material)
        sound.volume = settings.volume
        sound.setActive(active.audio)
        latency.setActive(active.any)

        if active.clickSounds {
            clicks.start { [weak self] in self?.sound.play(.click) }
        } else {
            clicks.stop()
        }
        if active.keySounds {
            startKeyboard(prompt: true)
        } else {
            keys.stop()
            isKeyboardListening = false
        }
    }

    private func startKeyboard(prompt: Bool) {
        guard !keys.isRunning else { return }
        let started = keys.start { [weak self] trigger in self?.sound.play(trigger) }
        if !started, prompt, !hasRequestedKeyboardPermission {
            hasRequestedKeyboardPermission = true
            KeyboardMonitor.requestPermission()
        }
        isKeyboardListening = started
        hasKeyboardPermission = started || KeyboardMonitor.hasPermission
    }
}
