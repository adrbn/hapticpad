/// Which services should run for a given configuration, so nothing runs that can't be felt or heard.
public struct ActiveFeedback: Equatable, Sendable {
    /// The multitouch stream, needed for any haptic input.
    public let touches: Bool
    public let clickSounds: Bool
    public let keySounds: Bool
    /// Texture sound. Independent of the touch inputs, so the material preview is heard
    /// even while Pointer, Scroll and Tap are all off.
    public let grainSounds: Bool

    public init(settings: Settings, hapticsReady: Bool) {
        let on = settings.isEnabled
        touches = on && hapticsReady
            && (settings.pointerEnabled || settings.scrollEnabled || settings.tapEnabled)
        clickSounds = on && settings.clickSoundEnabled
        keySounds = on && settings.keyboardSoundEnabled
        grainSounds = on && hapticsReady && settings.textureSoundEnabled
    }

    /// Whether the audio engine is needed.
    public var audio: Bool { clickSounds || keySounds || grainSounds }

    public var any: Bool { touches || audio }
}
