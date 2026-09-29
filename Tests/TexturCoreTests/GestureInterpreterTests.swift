import Testing
@testable import TexturCore

private func touch(_ id: Int32, _ x: Double, _ y: Double, _ phase: TouchPhase = .touching) -> Touch {
    Touch(id: id, position: Vector2(x: x, y: y), phase: phase)
}

private func frame(_ time: Double, _ touches: Touch...) -> TouchFrame {
    TouchFrame(timestamp: time, touches: touches)
}

/// Feeds frames in order and returns the events produced by each one.
private func run(_ frames: [TouchFrame], configuration: GestureInterpreter.Configuration = .init()) -> [[GestureEvent]] {
    var interpreter = GestureInterpreter(configuration: configuration)
    var output: [[GestureEvent]] = []
    for item in frames {
        let (next, events) = interpreter.consume(item)
        interpreter = next
        output.append(events)
    }
    return output
}

@Suite("GestureInterpreter")
struct GestureInterpreterTests {
    @Test func singleFingerMovementEmitsPointerDelta() {
        let events = run([
            frame(0.00, touch(1, 10, 10)),
            frame(0.01, touch(1, 12, 10)),
        ])
        #expect(events[1] == [.pointer(delta: Vector2(x: 2, y: 0), timestamp: 0.01)])
    }

    @Test func twoFingersEmitScrollWithCentroidDelta() {
        let events = run([
            frame(0.00, touch(1, 10, 10), touch(2, 20, 10)),
            frame(0.01, touch(1, 10, 13), touch(2, 20, 13)),
        ])
        #expect(events[1] == [.scroll(delta: Vector2(x: 0, y: 3), timestamp: 0.01)])
    }

    @Test func changingFingerCountNeverProducesAJump() {
        let events = run([
            frame(0.00, touch(1, 10, 10)),
            frame(0.01, touch(1, 10, 10), touch(2, 40, 40)),
            frame(0.02, touch(2, 40, 40)),
        ])
        #expect(events[1].isEmpty)
        #expect(events[2].isEmpty)
    }

    @Test func threeFingerMovementIsLeftToTheSystem() {
        let events = run([
            frame(0.00, touch(1, 10, 10), touch(2, 20, 10), touch(3, 30, 10)),
            frame(0.01, touch(1, 15, 10), touch(2, 25, 10), touch(3, 35, 10)),
        ])
        #expect(events[1].isEmpty)
    }

    @Test func hoveringFingersAreIgnored() {
        let events = run([
            frame(0.00, touch(1, 10, 10), touch(2, 50, 50, .hovering)),
            frame(0.01, touch(1, 11, 10), touch(2, 60, 50, .hovering)),
        ])
        #expect(events[1] == [.pointer(delta: Vector2(x: 1, y: 0), timestamp: 0.01)])
    }

    @Test func restingThumbDoesNotTurnPointerMovementIntoScrolling() {
        let events = run([
            frame(0.00, touch(1, 10, 10), touch(2, 60, 5)),
            frame(0.01, touch(1, 13, 10), touch(2, 60.05, 5)),
        ])
        #expect(events[1] == [.pointer(delta: Vector2(x: 3, y: 0), timestamp: 0.01)])
    }

    @Test func fingersMovingAtDifferentSpeedsStillScroll() {
        let events = run([
            frame(0.00, touch(1, 10, 10), touch(2, 20, 10)),
            frame(0.01, touch(1, 10, 13), touch(2, 20, 12)),
        ])
        #expect(events[1] == [.scroll(delta: Vector2(x: 0, y: 2.5), timestamp: 0.01)])
    }

    @Test func fingerLandingEmitsTouchDown() {
        let events = run([
            frame(0.00),
            frame(0.01, touch(1, 10, 10)),
            frame(0.02, touch(1, 10, 10)),
        ])
        #expect(events[0].isEmpty)
        #expect(events[1] == [.touchDown(timestamp: 0.01)])
        #expect(events[2].isEmpty)
    }

    @Test func fingersLandingTogetherTickOnce() {
        let events = run([
            frame(0.00, touch(1, 10, 10)),
            frame(0.02, touch(1, 10, 10), touch(2, 25, 10)),
        ])
        #expect(events[0] == [.touchDown(timestamp: 0.00)])
        #expect(events[1].isEmpty)
    }

    @Test func tapWithAThumbRestingTicksAgain() {
        let events = run([
            frame(0.00, touch(1, 60, 5)),
            frame(0.50, touch(1, 60, 5), touch(2, 20, 30)),
        ])
        #expect(events[1] == [.touchDown(timestamp: 0.50)])
    }

    @Test func liftingOrHoveringFingersNeverTick() {
        let events = run([
            frame(0.00, touch(1, 10, 10, .hovering)),
            frame(0.01, touch(1, 10, 10, .lifting)),
        ])
        #expect(events.allSatisfy { $0.isEmpty })
    }

    @Test func threeFingerLandingIsLeftToTheSystem() {
        let events = run([
            frame(0.00, touch(1, 10, 10), touch(2, 20, 10), touch(3, 30, 10)),
        ])
        #expect(events[0].isEmpty)
    }
}

@Suite("Touch conversion")
struct TouchConversionTests {
    @Test func rawStatesMapToPhases() {
        #expect(TouchPhase(rawState: 3) == .touching)
        #expect(TouchPhase(rawState: 4) == .touching)
        #expect(TouchPhase(rawState: 5) == .lifting)
        for raw: Int32 in [0, 1, 2, 6, 7, 42] {
            #expect(TouchPhase(rawState: raw) == .hovering)
        }
    }

    @Test func normalizedPositionsBecomeMillimetres() {
        let surface = SurfaceSize(width: 120, height: 80)
        let converted = Touch(id: 4, normalizedX: 0.5, normalizedY: 0.25, surface: surface, rawState: 4)
        #expect(converted == Touch(id: 4, position: Vector2(x: 60, y: 20), phase: .touching))
    }

    @Test func unknownSurfaceFallsBackToATypicalTrackpad() {
        let surface = SurfaceSize(width: 0, height: -1)
        #expect(surface == SurfaceSize.fallback)
    }
}
