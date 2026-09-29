import AVFoundation
import TexturCore
import os

/// Plays synthesized click, key and grain sounds with low latency.
///
/// Buffers for the current profile and material are rendered once, and small
/// pools of player nodes let fast typing overlap without cutting sounds off.
/// Grains have their own pool, so a fast swipe never cuts a click short.
@MainActor
final class SoundPlayer {
    private static let sampleRate = 48_000.0
    private static let voices = 8
    private static let grainVoices = 4

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundPlayer.sampleRate, channels: 1)
    private let log = Logger(subsystem: "Textur", category: "audio")
    private var nodes: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var profile: SoundProfileID?
    private var buffers: [SoundTrigger: [AVAudioPCMBuffer]] = [:]
    private var melody = MelodyWalker(noteCount: SoundSynth.variantCount(profile: .kalimba, trigger: .click), seed: 1)
    private var lastVariant: [SoundTrigger: Int] = [:]
    private var grainNodes: [AVAudioPlayerNode] = []
    private var nextGrainVoice = 0
    private var grainMaterial: MaterialID?
    private var grainBuffers: [AVAudioPCMBuffer] = []
    private var lastGrainVariant: Int?
    private var configurationObserver: NSObjectProtocol?
    private var isActive = false

    init() {
        guard let format else { return }
        nodes = (0..<Self.voices).map { _ in AVAudioPlayerNode() }
        grainNodes = (0..<Self.grainVoices).map { _ in AVAudioPlayerNode() }
        for node in nodes + grainNodes {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterDeviceChange() }
        }
    }

    var volume: Double {
        get { Double(engine.mainMixerNode.outputVolume) }
        set { engine.mainMixerNode.outputVolume = Float(newValue) }
    }

    /// Renders the profile's sounds if it changed.
    func load(profile newProfile: SoundProfileID) {
        guard newProfile != profile, let format else { return }
        profile = newProfile
        lastVariant = [:]
        buffers = Dictionary(uniqueKeysWithValues: SoundTrigger.allCases.map { trigger in
            let count = SoundSynth.variantCount(profile: newProfile, trigger: trigger)
            let rendered = (0..<count).compactMap { variant in
                Self.buffer(
                    from: SoundSynth.render(profile: newProfile, trigger: trigger, variant: variant, sampleRate: Self.sampleRate),
                    format: format
                )
            }
            return (trigger, rendered)
        })
        melody = MelodyWalker(noteCount: SoundSynth.variantCount(profile: newProfile, trigger: .click), seed: UInt64.random(in: 1...UInt64.max))
    }

    /// Renders the material's grain sounds if it changed.
    func load(material newMaterial: MaterialID) {
        guard newMaterial != grainMaterial, let format else { return }
        grainMaterial = newMaterial
        lastGrainVariant = nil
        grainBuffers = (0..<SoundSynth.grainVariantCount).compactMap { variant in
            Self.buffer(from: SoundSynth.renderGrain(material: newMaterial, variant: variant, sampleRate: Self.sampleRate), format: format)
        }
    }

    /// Starts or stops the audio engine; it only runs while a sound option is on.
    func setActive(_ active: Bool) {
        isActive = active
        if active, !engine.isRunning {
            do {
                try engine.start()
            } catch {
                log.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            }
        } else if !active, engine.isRunning {
            (nodes + grainNodes).forEach { $0.stop() }
            engine.stop()
        }
    }

    func play(_ trigger: SoundTrigger) {
        guard engine.isRunning, let candidates = buffers[trigger], !candidates.isEmpty else { return }
        let variant = chooseVariant(for: trigger, count: candidates.count)
        let node = nodes[nextVoice]
        nextVoice = (nextVoice + 1) % nodes.count
        node.scheduleBuffer(candidates[variant], at: nil, options: .interrupts)
        if !node.isPlaying {
            node.play()
        }
    }

    func playGrain(_ strength: PulseStrength) {
        guard engine.isRunning, !grainBuffers.isEmpty else { return }
        // Random, but never the same variant twice in a row, so a steady swipe doesn't buzz.
        let options = grainBuffers.indices.filter { $0 != lastGrainVariant || grainBuffers.count == 1 }
        let variant = options.randomElement() ?? 0
        lastGrainVariant = variant
        let node = grainNodes[nextGrainVoice]
        nextGrainVoice = (nextGrainVoice + 1) % grainNodes.count
        node.volume = Float(SoundSynth.grainLevel(for: strength))
        node.scheduleBuffer(grainBuffers[variant], at: nil, options: .interrupts)
        if !node.isPlaying {
            node.play()
        }
    }

    /// Plays one grain sound per grain of a phrase, at each grain's delay.
    func playGrains(_ grains: [[Pulse]]) {
        for grain in grains {
            guard let strength = grain.peakStrength else { continue }
            let delay = grain.map(\.delay).min() ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.playGrain(strength) }
            }
        }
    }

    private func chooseVariant(for trigger: SoundTrigger, count: Int) -> Int {
        if profile?.isMelodic == true {
            let (next, note) = melody.next()
            melody = next
            return min(note, count - 1)
        }
        // Random, but never the same variant twice in a row.
        let previous = lastVariant[trigger]
        let options = (0..<count).filter { $0 != previous || count == 1 }
        let variant = options.randomElement() ?? 0
        lastVariant[trigger] = variant
        return variant
    }

    private func restartAfterDeviceChange() {
        guard isActive, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            log.error("Audio engine failed to restart: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
