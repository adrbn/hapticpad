import CMultitouch
import Dispatch
import Foundation
import TexturCore

/// A touch copied out of the C frame so it can cross threads.
struct RawTouch: Sendable {
    let id: Int32
    let state: Int32
    let x: Double
    let y: Double
}

/// Receives contact frames, interprets gestures and plays the matching grains.
///
/// All mutable state lives on `queue`; the multitouch callback thread only
/// copies the frame and hops onto it.
final class FeedbackPipeline: @unchecked Sendable {
    /// Two-finger scrolling covers ground fast; wider grains keep it from buzzing.
    static let scrollSpacingFactor = 1.6

    private let queue = DispatchQueue(label: "textur.pipeline", qos: .userInteractive)
    private let actuators: HapticActuators
    /// Called on the pipeline queue for each grain played while texture sound is on.
    private let onGrain: @Sendable (PulseStrength) -> Void
    private var settings = Settings.default
    private var surfaces: [UInt64: SurfaceSize] = [:]
    private var channels: [UInt64: DeviceChannel] = [:]

    /// Per-trackpad gesture state and texture engines.
    private struct DeviceChannel {
        let interpreter: GestureInterpreter
        let pointer: TextureEngine
        let scroll: TextureEngine
    }

    init(actuators: HapticActuators, onGrain: @escaping @Sendable (PulseStrength) -> Void = { _ in }) {
        self.actuators = actuators
        self.onGrain = onGrain
    }

    func update(settings newSettings: Settings) {
        queue.async { [self] in
            let textureChanged = newSettings.material != settings.material
                || newSettings.strength != settings.strength
                || newSettings.grainScale != settings.grainScale
            settings = newSettings
            if textureChanged {
                channels = channels.mapValues(reconfigured)
            }
        }
    }

    func update(trackpads: [Trackpad]) {
        queue.async { [self] in
            surfaces = Dictionary(trackpads.map { ($0.id, $0.surface) }, uniquingKeysWith: { first, _ in first })
            channels = channels.filter { surfaces[$0.key] != nil }
        }
    }

    func receive(deviceID: UInt64, touches: [RawTouch], timestamp: Double) {
        queue.async { [self] in
            process(deviceID: deviceID, touches: touches, timestamp: timestamp)
        }
    }

    // MARK: - Queue-confined work

    private func process(deviceID: UInt64, touches: [RawTouch], timestamp: Double) {
        guard settings.isEnabled else { return }
        let surface = surfaces[deviceID] ?? .fallback
        let frame = TouchFrame(
            timestamp: timestamp,
            touches: touches.map { Touch(id: $0.id, normalizedX: $0.x, normalizedY: $0.y, surface: surface, rawState: $0.state) }
        )
        let channel = channels[deviceID] ?? makeChannel(deviceID: deviceID)
        let (interpreter, events) = channel.interpreter.consume(frame)
        var pointer = channel.pointer
        var scroll = channel.scroll
        for event in events {
            switch event {
            case let .pointer(delta, time):
                let (next, pulses) = pointer.advance(by: delta, at: time)
                pointer = next
                if settings.pointerEnabled { play(grain: pulses, on: deviceID) }
            case let .scroll(delta, time):
                let (next, pulses) = scroll.advance(by: delta, at: time)
                scroll = next
                if settings.scrollEnabled { play(grain: pulses, on: deviceID) }
            case .touchDown:
                if settings.tapEnabled {
                    actuators.play(MaterialCatalog.material(for: settings.material).tapGrain(strength: settings.strength), on: deviceID)
                }
            }
        }
        let lifted = !frame.touches.contains { $0.phase == .touching }
        channels[deviceID] = DeviceChannel(
            interpreter: interpreter,
            pointer: lifted ? pointer.reset() : pointer,
            scroll: lifted ? scroll.reset() : scroll
        )
    }

    private func play(grain pulses: [Pulse], on deviceID: UInt64) {
        actuators.play(pulses, on: deviceID)
        if settings.textureSoundEnabled, let peak = pulses.peakStrength {
            onGrain(peak)
        }
    }

    private func makeChannel(deviceID: UInt64) -> DeviceChannel {
        let material = MaterialCatalog.material(for: settings.material)
        let seed = deviceID ^ UInt64(Date().timeIntervalSince1970 * 1000)
        return DeviceChannel(
            interpreter: GestureInterpreter(),
            pointer: TextureEngine(material: material, tuning: tuning(spacingFactor: 1), seed: seed),
            scroll: TextureEngine(material: material, tuning: tuning(spacingFactor: Self.scrollSpacingFactor), seed: ~seed)
        )
    }

    private func reconfigured(_ channel: DeviceChannel) -> DeviceChannel {
        let material = MaterialCatalog.material(for: settings.material)
        return DeviceChannel(
            interpreter: channel.interpreter,
            pointer: channel.pointer.reconfigured(material: material, tuning: tuning(spacingFactor: 1)),
            scroll: channel.scroll.reconfigured(material: material, tuning: tuning(spacingFactor: Self.scrollSpacingFactor))
        )
    }

    private func tuning(spacingFactor: Double) -> TextureTuning {
        TextureTuning(strength: settings.strength, grainScale: settings.grainScale, spacingFactor: spacingFactor)
    }
}

/// Owns the multitouch stream and forwards frames to the pipeline.
@MainActor
final class TouchStream {
    private let pipeline: FeedbackPipeline
    /// The reference handed to the C bridge, kept retained until the bridge lets go of it.
    private var bridgeReference: Unmanaged<FeedbackPipeline>?
    private(set) var isRunning = false

    init(pipeline: FeedbackPipeline) {
        self.pipeline = pipeline
    }

    deinit {
        // Stop before releasing: the bridge holds an unretained copy of the reference.
        tx_multitouch_stop()
        bridgeReference?.release()
    }

    /// Starts every haptic trackpad. Returns how many are streaming.
    @discardableResult
    func start() -> Int {
        let reference = Unmanaged.passRetained(pipeline)
        let started = Int(tx_multitouch_start(touchFrameCallback, reference.toOpaque()))
        // Starting replaced any previous stream, which no longer uses its reference.
        bridgeReference?.release()
        bridgeReference = reference
        isRunning = started > 0
        return started
    }

    func stop() {
        tx_multitouch_stop()
        bridgeReference?.release()
        bridgeReference = nil
        isRunning = false
    }
}

/// C entry point for contact frames; runs on the framework's thread.
private let touchFrameCallback: TXFrameHandler = { deviceID, touches, count, timestamp, context in
    guard let context else { return }
    let pipeline = Unmanaged<FeedbackPipeline>.fromOpaque(context).takeUnretainedValue()
    let buffer = UnsafeBufferPointer(start: touches, count: touches == nil ? 0 : Int(max(count, 0)))
    let copied = buffer.map { RawTouch(id: $0.identifier, state: $0.state, x: Double($0.x), y: Double($0.y)) }
    pipeline.receive(deviceID: deviceID, touches: copied, timestamp: timestamp)
}
