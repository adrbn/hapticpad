# How HapticPad works

## Goal

A free, open-source menu bar app that makes the Force Touch trackpad feel textured during everyday use (pointer movement, scrolling, taps), with optional sounds for clicks and typing. Offline, no account, no paid tier.

## Constraints

- `NSHapticFeedbackManager` only offers three patterns and is ignored for menu bar (accessory) apps that are not frontmost, so it cannot drive textures. HapticPad uses Apple's private `MultitouchSupport` framework for both touch input and actuation.
- Private symbols are resolved with `dlopen` and `dlsym`. A missing symbol disables haptics instead of crashing, and sounds keep working.
- The app is not sandboxed (the sandbox blocks the multitouch device and event taps), so it ships outside the Mac App Store, signed with Developer ID and notarized.

## Waveforms

The trackpad firmware embeds its actuation table (`__TEXT,__tpad_act_plist` in MultitouchSupport). IDs 1, 3 and 5 are silent Gaussian bumps of about 7 ms (amplitude about 16 to 23), IDs 2 and 4 add short tones (about 27 to 35), and ID 6 is the strongest tap (about 37 to 50). HapticPad maps its four pulse strengths to 1, 5, 4 and 6.

## Architecture

```
MultitouchSupport ──frames──▶ CMultitouch (C bridge, dlopen)
                                   │ HPTouch[] on the framework thread
                                   ▼
                          FeedbackPipeline (serial queue)
                 TouchFrame (mm) ─▶ GestureInterpreter ─▶ GestureEvent
                                   │ pointer / scroll / touch-down
                                   ▼
                  TextureEngine (per device, per input) ─▶ [Pulse]
                                   ▼
                     HapticActuators (serial queue) ─▶ MTActuatorActuate

NSEvent monitor (clicks) ─┐
CGEventTap (keys) ────────┴▶ SoundPlayer (AVAudioEngine, synthesized buffers)
```

### HapticPadCore (pure Swift, unit tested)

- `GestureInterpreter`: immutable state machine.
  - Movement is only reported while the same set of fingers stays down, which prevents jumps when fingers land or lift.
  - One finger is pointer movement. Two fingers are scrolling, unless one of them barely moves (less than a quarter of the other): that is a resting thumb during a click-drag, and the moving finger drives the pointer.
  - A touch-down is reported when a finger lands, with at most two fingers down and at most one every 0.1 s. Haptics are only felt while a finger touches the surface, so a tap is confirmed as the finger lands, not when it lifts.
- `TextureEngine`: immutable. Buffers sub-0.08 mm movement so sensor noise cancels out, weighs travel by the material's axis weights, crosses randomized gaps, picks the strongest grain when a frame crosses several, and drops grains closer than 10 ms apart.
- `Material` and `MaterialCatalog`: data only (spacing, jitter, axis weights, grain pulses, accent, skip chance).
- `SoundSynth`: deterministic synthesis of every sound, with faded edges and normalized peaks.
- `Settings`: forgiving decoding (defaults for missing keys, a fallback for unknown values, clamped numbers).

### App

- `AppModel` owns the services and starts or stops them from the settings: the touch stream only runs while an input is on, and the audio engine only while a sound option is on.
- While any feedback runs, a `latencyCritical` activity keeps App Nap from throttling the app, so grains and sounds stay attached to the finger.
- Trackpads are found again on wake, when IOKit reports an `AppleMultitouchDevice` appearing or disappearing (a Magic Trackpad that connects after login), and whenever the panel opens. The hardware is only rebuilt when the list changed.
- The C bridge guards its stream state with a read-write lock. Start and stop take the write side; the frame callback only tries the read side and drops the frame if it can't get it, because stopping a device may wait for the framework thread. Once stop returns, the old handler and context are never used again, and `TouchStream` releases the pipeline reference it gave the bridge.
- `--diagnose` prints the trackpads, plays each waveform and counts contact frames for three seconds. `--snapshot <folder>` renders the README hero.

## Testing

- Unit tests cover gestures, textures, materials, settings and sound synthesis (`swift test`).
- Hardware checks: `HapticPad --diagnose` confirms that each waveform is accepted by the actuator and that touches arrive. The actual feel is judged by hand.
