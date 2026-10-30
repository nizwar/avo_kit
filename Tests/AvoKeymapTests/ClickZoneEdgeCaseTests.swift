import AvoInput
import Foundation
import Testing
@testable import AvoKeymap

// Click zones and click areas where play gets in the way: a key and a click
// on one control, a click whose release never came, an anchor dragged by
// the click, a click area that locks the mouse.

/// 2400 x 1080 landscape display.
private let W = 2400.0, H = 1080.0

private func engine(_ profile: KeymapProfile) -> KeymapEngine {
    KeymapEngine(profile: profile, displayID: 7, width: W, height: H, touchSpread: 0)
}

private func summary(_ events: [TouchEvent]) -> [String] {
    events.map { event in
        let pointers = event.pointers.map { "\($0.id)@\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }.joined(separator: " ")
        return "\(event.action)[\(event.actionIndex)] \(pointers)"
    }
}

private func downs(_ lines: [String]) -> Int { lines.filter { $0.hasPrefix("down") || $0.hasPrefix("pointerDown") }.count }

private func eye() -> Control {
    Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1), adsSensitivity: AxisPair(x: 1, y: 1),
                                  exponent: 1, deadzone: 0, invertY: false, stick: nil))
}

/// A zone around the screen's middle (x 1080…1320, y 432…648).
private let middle = ClickZone(area: NormalizedRect(0.45, 0.4, 0.55, 0.6), shape: .rectangle)

private func emote() -> Control {
    Control(id: "emote", kind: .anchor(NormalizedPoint(0.5, 0.5), radius: 0.2), triggers: [.key(.t)], clickZone: middle)
}

@Suite struct ClickZoneEdgeCaseTests {
    // MARK: A key and a click on one control

    /// An anchor held by its key, its zone clicked and let go: the key still holds it.
    @Test func aZonesReleaseLeavesAnAnchorItsKeyHolds() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [emote()]))
        _ = e.handle(.keyDown(.t), at: 0)
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0.1)
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 0.2)
        #expect(e.activeTouchCount == 1, "T is still held")
        _ = e.handle(.keyUp(.t), at: 0.3)
        #expect(e.activeTouchCount == 0)
    }

    /// The other way round: clicked first, then its key, then the click let go.
    @Test func aZonesReleaseLeavesAnAnchorItsKeyPressedSince() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [emote()]))
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        _ = e.handle(.keyDown(.t), at: 0.1)
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 0.2)
        #expect(e.activeTouchCount == 1, "T is still held")
    }

    /// Aim down sights (held): the click's release leaves it to its key, still aiming down sights.
    @Test func aZonesReleaseLeavesAimDownSightsItsKeyHolds() {
        let ads = Control(id: "ads", kind: .ads(NormalizedPoint(0.5, 0.5), toggle: false), triggers: [.key(.q)], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye(), ads], fps: FPSSettings(aimControl: "eye")))
        _ = e.handle(.keyDown(.q), at: 0)
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0.1)
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 0.2)
        #expect(e.activeTouchCount == 1, "Q is still held")
        #expect(e.adsActive)
        _ = e.handle(.keyUp(.q), at: 0.3)
        #expect(!e.adsActive)
    }

    /// Two keys on one anchor: letting go of one leaves it to the other.
    @Test func twoKeysOnOneAnchorHoldItTogether() {
        let anchor = Control(id: "emote", kind: .anchor(NormalizedPoint(0.5, 0.5)), triggers: [.key(.t), .gamepad(.y)])
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [anchor]))
        _ = e.handle(.keyDown(.t), at: 0)
        _ = e.handle(.gamepadButton(.y, pressed: true), at: 0.1)
        _ = e.handle(.keyUp(.t), at: 0.2)
        #expect(e.activeTouchCount == 1)
        _ = e.handle(.gamepadButton(.y, pressed: false), at: 0.3)
        #expect(e.activeTouchCount == 0)
    }

    /// A repeat tap held by its key and clicked on its zone at once taps at
    /// its own pace, not twice as fast.
    @Test func aKeyAndAZoneTogetherKeepARepeatTapsPace() {
        let rapid = Control(id: "rapid", kind: .repeatTap(NormalizedPoint(0.5, 0.5), intervalMilliseconds: 100), triggers: [.key(.r)],
                            clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [rapid]))
        var lines = summary(e.handle(.keyDown(.r), at: 0).events)
        lines += summary(e.handle(.fingerDown(x: 1200, y: 540), at: 0.05).events)
        var t = 0.06
        while t <= 1.0 {
            lines += summary(e.tick(at: t))
            t += 0.01
        }
        #expect((10...11).contains(downs(lines)), "\(downs(lines)) taps in one second at a 100 ms interval")
        // The key let go, the click still holds it; then the click lets go too.
        _ = e.handle(.keyUp(.r), at: 1.05)
        lines = summary(e.tick(at: 1.25))
        #expect(downs(lines) == 2)
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 1.3)
        lines = summary(e.tick(at: 1.5) + e.tick(at: 2))
        #expect(downs(lines) == 0)
        // Pressed again later: it starts at once.
        #expect(downs(summary(e.handle(.keyDown(.r), at: 3).events)) == 1)
    }

    // MARK: An anchor dragged by the click

    /// An anchor pressed by its zone follows the mouse: with the button
    /// down macOS sends drags, so the host reports the cursor and the
    /// anchor follows its reports.
    @Test func anAnchorPressedByItsZoneFollowsTheCursor() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [emote()]))
        // Clicked off its point, at the zone's edge.
        _ = e.handle(.fingerDown(x: 1100, y: 540), at: 0)
        #expect(e.activeTouchCount == 1)
        #expect(e.isFollowingCursor)
        let dragged = summary(e.handle(.cursor(x: 1200, y: 600), at: 0.05).events + e.tick(at: 0.1))
        #expect(dragged == ["move[0] 0@1300,600"])
        // Never further than its reach (0.2 of the height: 216 px).
        let far = summary(e.handle(.cursor(x: 1700, y: 600), at: 0.15).events + e.tick(at: 0.2))
        #expect(far == ["move[0] 0@1415,561"])
        _ = e.handle(.fingerUp(x: 1700, y: 600), at: 0.3)
        #expect(e.activeTouchCount == 0)
        #expect(!e.isFollowingCursor)
    }

    /// An anchor on the right button follows the reports while it is held;
    /// one on a key follows the mouse's moves, not the reports.
    @Test func anAnchorFollowsTheReportsOnlyWhileAMouseButtonIsDown() {
        let right = Control(id: "wheel", kind: .anchor(NormalizedPoint(0.5, 0.5)), triggers: [.mouse(.right)])
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [right]))
        _ = e.handle(.mouseDown(.right), at: 0)
        #expect(e.isFollowingCursor)
        // The first report is where the cursor is; the next ones move it.
        _ = e.handle(.cursor(x: 500, y: 500), at: 0.01)
        let moved = summary(e.handle(.cursor(x: 550, y: 480), at: 0.02).events + e.tick(at: 0.03))
        #expect(moved == ["move[0] 0@1250,520"])
        _ = e.handle(.mouseUp(.right), at: 0.1)

        var keyed = engine(KeymapProfile(package: "x", name: "x", controls: [emote()]))
        _ = keyed.handle(.keyDown(.t), at: 0)
        #expect(!keyed.isFollowingCursor)
        _ = keyed.handle(.cursor(x: 500, y: 500), at: 0.01)
        #expect(summary(keyed.handle(.cursor(x: 600, y: 500), at: 0.02).events + keyed.tick(at: 0.03)).isEmpty)
        #expect(summary(keyed.handle(.pointerMoved(dx: 40, dy: 0), at: 0.04).events) == ["move[0] 0@1240,540"])
    }

    // MARK: A click whose release never came

    /// A zone's click is a click the host can see held, so its check of the
    /// mouse's buttons can let it go.
    @Test func aZonesClickIsAClickHeld() {
        let tap = Control(id: "bag", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.b)], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [tap]))
        #expect(!e.isClickDown)
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        #expect(e.isClickDown)
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 0.1)
        #expect(!e.isClickDown)
        _ = e.handle(.fingerDown(x: 100, y: 100), at: 1)
        #expect(e.isClickDown)
    }

    /// A zone's click whose release was lost, then a click on the game: the
    /// zone lets go first, and the new click's finger lifts with its own release.
    @Test func aLostZoneReleaseEndsWithTheNextClick() {
        let tap = Control(id: "bag", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.b)], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [tap]))
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        let next = summary(e.handle(.fingerDown(x: 300, y: 300), at: 1).events)
        #expect(next == ["up[0] 0@1200,540", "down[0] 0@300,300"])
        _ = e.handle(.fingerUp(x: 300, y: 300), at: 1.1)
        _ = e.tick(at: 2)
        #expect(e.activeTouchCount == 0)
    }

    /// A second zone clicked before the first one's release came: the first lets go.
    @Test func aSecondZonesClickLetsTheFirstGo() {
        let a = Control(id: "a", kind: .hold(NormalizedPoint(0.2, 0.2)), triggers: [.key(.a)],
                        clickZone: ClickZone(area: NormalizedRect(0.15, 0.15, 0.25, 0.25), shape: .rectangle))
        let b = Control(id: "b", kind: .hold(NormalizedPoint(0.8, 0.8)), triggers: [.key(.b)],
                        clickZone: ClickZone(area: NormalizedRect(0.75, 0.75, 0.85, 0.85), shape: .rectangle))
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [a, b]))
        _ = e.handle(.fingerDown(x: 480, y: 216), at: 0)
        _ = e.handle(.fingerDown(x: 1920, y: 864), at: 0.5)
        #expect(e.activeTouchCount == 1, "b's hold only")
        _ = e.handle(.fingerUp(x: 1920, y: 864), at: 0.6)
        _ = e.tick(at: 1)
        #expect(e.activeTouchCount == 0)
    }

    /// A click on the game whose release was lost, then another: the first
    /// finger lifts where it was instead of being dragged to the second.
    @Test func aLostReleaseOnTheGameLiftsTheFingerBeforeTheNextClick() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: []))
        _ = e.handle(.fingerDown(x: 100, y: 100), at: 0)
        #expect(summary(e.handle(.fingerDown(x: 500, y: 500), at: 1).events) == ["up[0] 0@100,100", "down[0] 0@500,500"])
    }

    // MARK: A click area that locks the mouse

    /// The inventory's Close button, a click area passing the click to the
    /// game that goes back to combat and locks the mouse: its mouseUp comes
    /// where the host parked the hidden cursor (the view's middle), and the
    /// finger lifts where it touched, a tap on Close and no drag.
    @Test func aClickAreaThatLocksTheMouseTapsTheGameWhereItWasClicked() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            eye(),
            Control(id: "close", kind: .clickArea(NormalizedRect(0.9, 0, 1, 0.1), passThrough: true), modes: ["bag"],
                    actions: [.switchMode("combat"), .lockMouse]),
        ], fps: FPSSettings(aimControl: "eye"), modes: [KeymapMode(id: "bag", name: "Inventory"), KeymapMode(id: "combat", name: "Combat")])
        #expect(profile.validate().isEmpty)
        var e = engine(profile)
        let down = e.handle(.fingerDown(x: 2300, y: 50), at: 0)
        #expect(down.pointerLock == true)
        #expect(down.mode == "combat")
        let up = summary(e.handle(.fingerUp(x: 1200, y: 540), at: 0.08).events)
        #expect(!up.contains { $0.hasPrefix("move") }, "\(up)")
        #expect(up.last?.contains("@2300,50") == true, "\(up)")
        #expect(e.activeTouchCount == 1, "the eye's finger")
    }

    // MARK: Checked to work

    /// A zone over a click area: the zone's control is pressed, and the
    /// click area under it does nothing (one click, one owner).
    @Test func aZoneOverAClickAreaTakesTheClick() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "area", kind: .clickArea(NormalizedRect(0.4, 0.4, 0.6, 0.6), passThrough: false), actions: [.switchMode("b")]),
            Control(id: "tap", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.t)], clickZone: middle),
        ], modes: [KeymapMode(id: "a", name: "A"), KeymapMode(id: "b", name: "B")])
        #expect(profile.validate().isEmpty)
        var e = engine(profile)
        let out = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        #expect(out.mode == nil)
        #expect(e.activeTouchCount == 1)
    }

    @Test func everyKindWithAZoneIsPressedByAClickAndLetGoWithIt() {
        let p = NormalizedPoint(0.5, 0.5)
        let kinds: [(String, Control.Kind)] = [
            ("tap", .tap(p)), ("hold", .hold(p)), ("repeat", .repeatTap(p, intervalMilliseconds: 100)), ("anchor", .anchor(p, radius: 0.2)),
            ("adsToggle", .ads(p, toggle: true)), ("adsHold", .ads(p, toggle: false)),
            ("swipe", .swipe(from: p, to: NormalizedPoint(0.5, 0.3), milliseconds: 100)),
            ("macro", .macro([.tap(p), .wait(milliseconds: 50), .tap(p)])), ("move", .mobaMove(center: p, radius: 0.12)),
            ("skill", .smartCast(p, radius: 0.1, reach: 0.35)),
        ]
        for (name, kind) in kinds {
            let control = Control(id: name, kind: kind, triggers: [.key(.t)], clickZone: middle)
            #expect(control.canHaveClickZone, "\(name)")
            let profile = KeymapProfile(package: "x", name: "x", controls: [control])
            #expect(profile.validate().isEmpty, "\(name): \(profile.validate())")
            var e = engine(profile)
            let down = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
            #expect(down.consumed, "\(name)")
            #expect(e.activeTouchCount == 1, "\(name): \(summary(down.events))")
            #expect(e.handle(.fingerUp(x: 1200, y: 540), at: 0.2).consumed, "\(name)")
            _ = e.tick(at: 0.5)
            _ = e.tick(at: 1)
            #expect(e.activeTouchCount == 0, "\(name)")
        }
        // A hotkey's zone does its actions and touches nothing.
        let hotkey = Control(id: "h", kind: .hotkey, triggers: [.key(.h)], actions: [.switchMode("b")], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [hotkey], modes: [KeymapMode(id: "a", name: "A"), KeymapMode(id: "b", name: "B")]))
        let out = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        #expect(out.mode == "b")
        #expect(out.events.isEmpty)
    }

    @Test func aZoneWhoseActionLocksTheMouseStillLetsGoOnRelease() {
        let tap = Control(id: "fight", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.f)], actions: [.lockMouse], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye(), tap], fps: FPSSettings(aimControl: "eye")))
        #expect(e.handle(.fingerDown(x: 1200, y: 540), at: 0).pointerLock == true)
        #expect(e.activeTouchCount == 2, "the tap and the eye")
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 0.2)
        #expect(e.activeTouchCount == 1, "the eye's finger only")
    }

    @Test func overlappingZonesPressBoth() {
        let a = Control(id: "a", kind: .tap(NormalizedPoint(0.48, 0.5)), triggers: [.key(.a)], clickZone: middle)
        let b = Control(id: "b", kind: .tap(NormalizedPoint(0.52, 0.5)), triggers: [.key(.b)], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [a, b]))
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        #expect(e.activeTouchCount == 2)
        _ = e.handle(.fingerUp(x: 1200, y: 540), at: 0.1)
        #expect(e.activeTouchCount == 0)
    }

    @Test func focusLostMidClickAndAStrayFingerUp() {
        let hold = Control(id: "bag", kind: .hold(NormalizedPoint(0.5, 0.5)), triggers: [.key(.b)], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [hold]))
        _ = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        _ = e.reset()
        #expect(e.activeTouchCount == 0)
        #expect(e.handle(.fingerUp(x: 1200, y: 540), at: 0.1).events.isEmpty)
        var fresh = engine(KeymapProfile(package: "x", name: "x", controls: [hold]))
        #expect(fresh.handle(.fingerUp(x: 1, y: 1), at: 0).events.isEmpty)
    }

    @Test func zonesOfAnotherModeLeaveTheClickToTheGame() {
        let tap = Control(id: "bag", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.b)], modes: ["b"], clickZone: middle)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [tap], modes: [KeymapMode(id: "a", name: "A"), KeymapMode(id: "b", name: "B")]))
        #expect(summary(e.handle(.fingerDown(x: 1200, y: 540), at: 0).events) == ["down[0] 0@1200,540"])
    }

    @Test func shapesAtTheirEdgesOnLandscapeAndPortrait() {
        let area = NormalizedRect(0.4, 0.4, 0.6, 0.6)
        for (w, h) in [(2400.0, 1080.0), (1080.0, 2400.0)] {
            let rect = ClickZone(area: area, shape: .rectangle), ellipse = ClickZone(area: area, shape: .ellipse), rounded = ClickZone(area: area, shape: .rounded)
            #expect(rect.contains(NormalizedPoint(0.4, 0.4), width: w, height: h))
            #expect(!ellipse.contains(NormalizedPoint(0.4, 0.4), width: w, height: h))
            #expect(!rounded.contains(NormalizedPoint(0.4, 0.4), width: w, height: h))
            // Half a pixel inside the middle of each side: all three.
            let ex = 0.5 / w, ey = 0.5 / h
            for p in [NormalizedPoint(0.5, 0.4 + ey), NormalizedPoint(0.5, 0.6 - ey), NormalizedPoint(0.4 + ex, 0.5), NormalizedPoint(0.6 - ex, 0.5)] {
                #expect(rect.contains(p, width: w, height: h) && ellipse.contains(p, width: w, height: h) && rounded.contains(p, width: w, height: h))
            }
            #expect(!rect.contains(NormalizedPoint(0.6001, 0.5), width: w, height: h))
            // The rounded corner's radius is a quarter of the shorter side on the screen.
            let r = min(0.2 * w, 0.2 * h) * 0.25
            let inside = NormalizedPoint(0.4 + (r - r * 0.7071 + 1) / w, 0.4 + (r - r * 0.7071 + 1) / h)
            #expect(rounded.contains(inside, width: w, height: h))
        }
    }

    @Test func zonesRoundTripAndBadOnesAreCaught() throws {
        let tap = Control(id: "t", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.t)],
                          clickZone: ClickZone(area: NormalizedRect(0.4, 0.4, 0.6, 0.6), shape: .ellipse))
        let profile = KeymapProfile(package: "x", name: "x", controls: [tap])
        #expect(try KeymapProfile.decode(profile.encoded()) == profile)
        let missingShape = try JSONDecoder().decode(ClickZone.self, from: Data(#"{"area": [0.1, 0.1, 0.2, 0.2]}"#.utf8))
        #expect(missingShape.shape == .rounded)
        // An unreadable zone is no zone; the control still loads.
        let json = Data("""
        {"schema": 1, "package": "x", "name": "x", "controls": [
          {"type": "tap", "id": "t", "position": [0.5, 0.5], "triggers": ["key:T"], "click_zone": {"area": [0.1, 0.2]}}
        ]}
        """.utf8)
        #expect(try KeymapProfile.decode(json).controls.first?.clickZone == nil)
        let inverted = Control(id: "t", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.t)],
                               clickZone: ClickZone(area: NormalizedRect(0.6, 0.4, 0.4, 0.6)))
        #expect(KeymapProfile(package: "x", name: "x", controls: [inverted]).validate() == ["t: click area is invalid"])
    }

    // MARK: What the host asks

    /// What the host asks before it keeps input from the game.
    @Test func whatTheMappingTakesNow() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            eye(),
            Control(id: "fire", kind: .tap(NormalizedPoint(0.8, 0.6)), triggers: [.mouse(.left)], layer: .locked),
            Control(id: "weapon", kind: .tap(NormalizedPoint(0.5, 0.9)), triggers: [.scrollUp]),
        ], fps: FPSSettings(aimControl: "eye"))
        var e = engine(profile)
        #expect(e.takes(.scrollUp) && !e.takes(.scrollDown))
        #expect(e.takes(.key(.f8)), "the mouse lock's key")
        #expect(!e.takes(.mouse(.left)), "with the mouse free a click is the game's")
        _ = e.setPointerLocked(true)
        #expect(e.takes(.mouse(.left)))
    }
}
