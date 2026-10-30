import AvoInput
import Foundation
import Testing
@testable import AvoKeymap

/// Where a finger lands (`KeymapEngine(touchSpread:)`): a press spreads
/// across its button's face, the eye's thumb within its box, and 0 spread
/// touches the exact points (the other suites run that way,
/// deterministically). Joysticks and drags keep their exact starts.
@Suite struct TouchSpreadTests {
    private static let W = 2400.0, H = 1080.0
    /// How far from its point a finger lands on a button at most: the spread
    /// is clipped at 80 % of the face's radius, and the half-pixel is the
    /// rounding of Float coordinates.
    private static let reach = Control.defaultSize * H / 2 * 0.8 + 0.51

    private func engine(_ controls: [Control], fps: FPSSettings? = nil, spread: Double = 1) -> KeymapEngine {
        KeymapEngine(profile: KeymapProfile(package: "com.example.game", name: "Test", controls: controls, fps: fps),
                     displayID: 7, width: Self.W, height: Self.H, touchSpread: spread)
    }

    private typealias Spot = (x: Double, y: Double)

    /// Where each finger went down in `events` (the first finger's).
    private func downs(_ events: [TouchEvent]) -> [Spot] {
        events.filter { $0.action == .down }.map { (Double($0.pointers[0].x), Double($0.pointers[0].y)) }
    }

    private func places(_ spots: [Spot]) -> Set<String> {
        Set(spots.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" })
    }

    /// `presses` presses of Space on `control`, each let go and lifted
    /// before the next: where each one's finger went down.
    private func landings(of control: Control, spread: Double = 1, presses: Int = 30) -> [Spot] {
        var e = engine([control], spread: spread)
        var spots: [Spot] = []
        for index in 0..<presses {
            let t = TimeInterval(index)
            spots += downs(e.handle(.keyDown(.space), at: t).events)
            spots += downs(e.handle(.keyUp(.space), at: t + 0.01).events)
            // Long enough for a macro's steps and a repeat's first tap.
            for step in 1...9 { spots += downs(e.tick(at: t + Double(step) * 0.1)) }
        }
        return spots
    }

    private func isOnTheButton(_ spot: Spot, at point: NormalizedPoint) -> Bool {
        hypot(spot.x - point.x * Self.W, spot.y - point.y * Self.H) <= Self.reach
    }

    @Test func tapsLandAcrossTheButtonNeverOnOnePixel() {
        let point = NormalizedPoint(0.5, 0.5)
        let spots = landings(of: Control(id: "jump", kind: .tap(point), triggers: [.key(.space)]))
        #expect(spots.count == 30)
        #expect(spots.allSatisfy { isOnTheButton($0, at: point) })
        #expect(places(spots).count >= 24)
    }

    @Test func zeroSpreadTouchesTheExactPoint() {
        let spots = landings(of: Control(id: "jump", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.space)]),
                             spread: 0, presses: 5)
        #expect(spots.count == 5)
        #expect(spots.allSatisfy { $0.x == 1200 && $0.y == 540 })
    }

    /// Every button has the one face (`Control.defaultSize` across): a
    /// `size` from Avo before b64, however big, does not throw a finger off it.
    @Test func anOldButtonSizeChangesNothing() {
        let point = NormalizedPoint(0.5, 0.5)
        let spots = landings(of: Control(id: "jump", kind: .tap(point), triggers: [.key(.space)], size: 0.9), presses: 40)
        #expect(spots.count == 40)
        #expect(spots.allSatisfy { isOnTheButton($0, at: point) })
    }

    /// Holds, Aim Down Sights (held or toggled), anchor taps, repeated taps
    /// (each repeat its own) and macro steps land on the button too.
    @Test(arguments: [
        Control.Kind.hold(NormalizedPoint(0.8, 0.6)),
        .ads(NormalizedPoint(0.8, 0.6), toggle: false),
        .ads(NormalizedPoint(0.8, 0.6), toggle: true),
        .anchor(NormalizedPoint(0.8, 0.6)),
        .repeatTap(NormalizedPoint(0.8, 0.6), intervalMilliseconds: 100),
        .macro([.tap(NormalizedPoint(0.8, 0.6)), .wait(milliseconds: 50), .hold(NormalizedPoint(0.8, 0.6), milliseconds: 60)]),
    ])
    func everyButtonPressSpreads(_ kind: Control.Kind) {
        let spots = landings(of: Control(id: "button", kind: kind, triggers: [.key(.space)]), presses: 12)
        #expect(spots.count >= 12)
        #expect(spots.allSatisfy { isOnTheButton($0, at: NormalizedPoint(0.8, 0.6)) })
        #expect(places(spots).count >= spots.count * 3 / 4)
    }

    /// A repeat's taps while the key is held: each one lands on its own spot.
    @Test func eachRepeatTapLandsOnItsOwnSpot() {
        let point = NormalizedPoint(0.8, 0.6)
        var e = engine([Control(id: "fire", kind: .repeatTap(point, intervalMilliseconds: 100), triggers: [.key(.space)])])
        var spots = downs(e.handle(.keyDown(.space), at: 0).events)
        // Repeats at 0.1 s, 0.2 s … 2 s (the next is due after the last tick).
        for step in 1...41 { spots += downs(e.tick(at: Double(step) * 0.05)) }
        #expect(spots.count == 21)
        #expect(spots.allSatisfy { isOnTheButton($0, at: point) })
        #expect(places(spots).count >= 17)
    }

    /// A fast wheel's notches: the one that taps at once and those that wait
    /// for the last finger to lift each land on their own spot.
    @Test func wheelNotchesAndTheTapsWaitingBehindThemSpread() {
        let point = NormalizedPoint(0.3, 0.4)
        var e = engine([Control(id: "next", kind: .tap(point), triggers: [.scrollUp])])
        var spots: [Spot] = []
        for _ in 0..<8 { spots += downs(e.handle(.scroll(dy: 1), at: 0).events) }
        #expect(spots.count == 1, "one finger at a time on the button")
        for step in 1...100 { spots += downs(e.tick(at: Double(step) * 0.01)) }
        #expect(spots.count == 8)
        #expect(spots.allSatisfy { isOnTheButton($0, at: point) })
        #expect(places(spots).count >= 6)
    }

    /// An anchor tap is dragged from where its finger landed, not from its
    /// point: the first move carries on from there without a jump.
    @Test func anAnchorIsDraggedFromWhereItLanded() {
        let point = NormalizedPoint(0.5, 0.5)
        for _ in 0..<10 {
            var e = engine([Control(id: "emote", kind: .anchor(point), triggers: [.key(.space)])])
            guard let landed = downs(e.handle(.keyDown(.space), at: 0).events).first else {
                Issue.record("no touch")
                return
            }
            #expect(isOnTheButton(landed, at: point))
            let moved = e.handle(.pointerMoved(dx: 30, dy: -20), at: 0.05).events
            guard let pointer = moved.last?.pointers.first else {
                Issue.record("no move")
                return
            }
            #expect(abs(Double(pointer.x) - (landed.x + 30)) <= 0.51)
            #expect(abs(Double(pointer.y) - (landed.y - 20)) <= 0.51)
        }
    }

    @Test func eyeTouchdownsVaryWithinTheBox() {
        let camera = Control(id: "camera", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7),
                                                      sensitivity: AxisPair(x: 1, y: 1), adsSensitivity: AxisPair(x: 1, y: 1),
                                                      exponent: 1, deadzone: 0, invertY: false, stick: nil))
        var e = engine([camera], fps: FPSSettings(aimControl: "camera"))
        var touchdowns: [Spot] = []
        for index in 0..<25 {
            touchdowns += downs(e.setPointerLocked(true))
            _ = e.setPointerLocked(false)
            _ = e.tick(at: TimeInterval(index) + 0.1)
        }
        #expect(touchdowns.count == 25)
        // Somewhere in the box, clear of its edge.
        for (x, y) in touchdowns {
            #expect((1201...2399).contains(x))
            #expect((109...755).contains(y))
        }
        #expect(places(touchdowns).count >= 20)
        // The thumb roams its box; it does not rest on one pixel.
        let furthest = touchdowns.map { hypot($0.x - 1800, $0.y - 432) }.max() ?? 0
        #expect(furthest > 40)
    }

    /// Reaching the edge of its box, the eye's finger touches down again on
    /// a fresh spot each time.
    @Test func theEyeTouchesDownAgainOnAFreshSpot() {
        let camera = Control(id: "camera", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7),
                                                      sensitivity: AxisPair(x: 1, y: 1), adsSensitivity: AxisPair(x: 1, y: 1),
                                                      exponent: 1, deadzone: 0, invertY: false, stick: nil))
        var e = engine([camera], fps: FPSSettings(aimControl: "camera"))
        var touchdowns = downs(e.setPointerLocked(true))
        for step in 0..<200 {
            let events = e.handle(.mouseMoved(dx: 50, dy: 0), at: Double(step) * 0.01).events
            touchdowns += events.filter { $0.action == .down }.map { (Double($0.pointers[0].x), Double($0.pointers[0].y)) }
        }
        #expect(touchdowns.count > 10, "the camera keeps turning")
        #expect(places(touchdowns).count >= touchdowns.count * 3 / 4)
        for (x, y) in touchdowns {
            #expect((1201...2399).contains(x))
            #expect((109...755).contains(y))
        }
    }

    /// An eye whose point sits on its box's edge, pushed that way: once its
    /// finger lands on the edge it stays down there, instead of lifting and
    /// touching down again on every movement of the mouse.
    @Test func anEyeOnItsEdgeStaysDownPushedThatWay() {
        let camera = Control(id: "camera", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7),
                                                      sensitivity: AxisPair(x: 1, y: 1), adsSensitivity: AxisPair(x: 1, y: 1),
                                                      exponent: 1, deadzone: 0, invertY: false, stick: nil,
                                                      origin: NormalizedPoint(1, 0.4)))
        var e = engine([camera], fps: FPSSettings(aimControl: "camera"))
        _ = e.setPointerLocked(true)
        // Pushes until a touch-down lands on the edge (about every other one does).
        for step in 0..<200 { _ = e.handle(.mouseMoved(dx: 50, dy: 0), at: Double(step) * 0.01) }
        var later: [TouchEvent] = []
        for step in 200..<260 { later += e.handle(.mouseMoved(dx: 50, dy: 0), at: Double(step) * 0.01).events }
        #expect(later.isEmpty)
        #expect(e.activeTouchCount == 1)
    }

    /// D-pads, MOBA joysticks, smart casts, swipes and scroll bars touch
    /// down exactly where their drag's math expects it, spread or not.
    @Test func joysticksAndDragsKeepTheirExactStart() {
        let dpad = Control(id: "move", kind: .dpad(center: NormalizedPoint(0.2, 0.7), radius: 0.1, up: .key(.w), down: .key(.s),
                                                    left: .key(.a), right: .key(.d), stick: nil))
        let moba = Control(id: "walk", kind: .mobaMove(center: NormalizedPoint(0.15, 0.75), radius: 0.12), triggers: [.key(.q)])
        let cast = Control(id: "skill", kind: .smartCast(NormalizedPoint(0.85, 0.8), radius: 0.1, reach: 0.35),
                           triggers: [.key(.e)])
        let swipe = Control(id: "slide", kind: .swipe(from: NormalizedPoint(0.6, 0.5), to: NormalizedPoint(0.6, 0.8), milliseconds: 100),
                            triggers: [.key(.r)])
        let bar = Control(id: "zoom", kind: .scrollBar(from: NormalizedPoint(0.9, 0.2), to: NormalizedPoint(0.9, 0.6), rest: 0.5, step: 0.1))
        let cases: [(KeymapEngine.Input, Spot)] = [
            (.keyDown(.w), (480, 756)),
            (.keyDown(.q), (360, 810)),
            (.keyDown(.e), (2040, 864)),
            (.keyDown(.r), (1440, 540)),
            (.scroll(dy: 1), (2160, 432)),
        ]
        for _ in 0..<5 {
            for (input, start) in cases {
                var e = engine([dpad, moba, cast, swipe, bar])
                let first = downs(e.handle(input, at: 0).events).first
                #expect(first.map { abs($0.x - start.x) < 0.01 && abs($0.y - start.y) < 0.01 } == true, "\(input)")
            }
        }
    }
}
