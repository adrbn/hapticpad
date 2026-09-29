import AVFoundation
import HapticPadCore
import os

/// Plays synthesized click and key sounds with low latency.
///
/// Buffers for the current profile are rendered once, and a small pool of
/// player nodes lets fast typing overlap without cutting sounds off.
@MainActor
final class SoundPlayer {
    private static let sampleRate = 48_000.0
    private static let voices = 8

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundPlayer.sampleRate, channels: 1)
    private let log = Logger(subsystem: "HapticPad", category: "audio")
    private var nodes: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var profile: SoundProfileID?
    private var buffers: [SoundTrigger: [AVAudioPCMBuffer]] = [:]
    private var melody = MelodyWalker(noteCount: SoundSynth.variantCount(profile: .kalimba, trigger: .click), seed: 1)
    private var lastVariant: [SoundTrigger: Int] = [:]
    private var configurationObserver: NSObjectProtocol?
    private var isActive = false

    init() {
        guard let format else { return }
        nodes = (0..<Self.voices).map { _ in AVAudioPlayerNode() }
        for node in nodes {
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
            nodes.forEach { $0.stop() }
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
