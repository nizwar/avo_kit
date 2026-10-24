import AvoInput
import Foundation
import Testing
@testable import AvoKeymap

// Play where it goes past the usual: a key pressed again fast, a stick left
// over when focus goes, a resize while aiming, an unbound click while
// aiming, a trackpad's flood of notches, layouts a newer Avo wrote.

private let W = 2400.0, H = 1080.0

private func engine(_ profile: KeymapProfile) -> KeymapEngine {
    KeymapEngine(profile: profile, displayID: 7, width: W, height: H)
}

private func summary(_ events: [TouchEvent]) -> [String] {
    events.map { event in
        let pointers = event.pointers.map { "\($0.id)@\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }.joined(separator: " ")
        return "\(event.action)[\(event.actionIndex)] \(pointers)"
    }
}

private func downs(_ events: [TouchEvent]) -> Int { events.filter { $0.action == .down || $0.action == .pointerDown }.count }

private func eye(stick: GamepadStick? = nil) -> Control {
    Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                  adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: stick))
}

private func walk(layer: ControlLayer? = nil) -> Control {
    Control(id: "move", kind: .dpad(center: NormalizedPoint(0.15, 0.7), radius: 0.12, up: .key(.w), down: .key(.s),
                                    left: .key(.a), right: .key(.d), stick: nil), layer: layer)
}

@Suite struct PlayEdgeCaseTests {
    // MARK: Keys pressed again fast

    /// Pressed, let go and pressed again within its interval: one chain, at its pace.
    @Test func aRepeatTapKeepsItsPaceThroughAQuickRepress() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "r", kind: .repeatTap(NormalizedPoint(0.5, 0.5), intervalMilliseconds: 150), triggers: [.key(.q)]),
        ])
        var e = engine(profile)
        var taps = downs(e.handle(.keyDown(.q), at: 0).events)
        taps += downs(e.handle(.keyUp(.q), at: 0.05).events)
        taps += downs(e.handle(.keyDown(.q), at: 0.10).events)
        var t = 0.10
        while t < 1.0 {
            t += 0.004
            taps += downs(e.tick(at: t))
        }
        // At 0, 0.15, 0.30 … 0.90.
        #expect(taps == 7, "\(taps) taps")
    }

    /// A tap let go before its shortest time and pressed again: the same finger stays down.
    @Test func aQuickRepressKeepsOneFingerOnTheButton() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [Control(id: "t", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.q)])])
        var e = engine(profile)
        _ = e.handle(.keyDown(.q), at: 0)
        _ = e.handle(.keyUp(.q), at: 0.01)
        #expect(e.handle(.keyDown(.q), at: 0.02).events.isEmpty)
        _ = e.tick(at: 0.1)
        #expect(e.activeTouchCount == 1, "held while the key is")
        _ = e.handle(.keyUp(.q), at: 0.2)
        #expect(e.activeTouchCount == 0)
    }

    /// A swipe on the wheel and a trackpad's flood of notches: one swipe at
    /// a time, so the joystick still finds a finger.
    @Test func manyNotchesStartOneSwipeAtATime() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "sw", kind: .swipe(from: NormalizedPoint(0.5, 0.6), to: NormalizedPoint(0.5, 0.3), milliseconds: 300), triggers: [.scrollUp]),
            walk(),
        ])
        var e = engine(profile)
        var started = 0
        for i in 0..<40 { started += downs(e.handle(.scroll(dy: 1), at: Double(i) * 0.008).events) }
        #expect(started == 2, "a swipe from 0 and one from 0.304")
        #expect(downs(e.handle(.keyDown(.w), at: 0.33).events) == 1)
    }

    @Test func aMacroRunsOnceAtATime() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "combo", kind: .macro([.tap(NormalizedPoint(0.5, 0.5)), .wait(milliseconds: 100), .tap(NormalizedPoint(0.6, 0.5))]),
                    triggers: [.key(.c)]),
        ])
        var e = engine(profile)
        var taps = downs(e.handle(.keyDown(.c), at: 0).events)
        _ = e.handle(.keyUp(.c), at: 0.01)
        taps += downs(e.handle(.keyDown(.c), at: 0.05).events)
        var t = 0.05
        while t < 0.5 {
            t += 0.01
            taps += downs(e.tick(at: t))
        }
        #expect(taps == 2, "one run: its two taps")
    }

    // MARK: Focus, resizes and the locked mouse

    /// A stick held over when focus goes: its release may never come, so it aims no more.
    @Test func focusLostForgetsTheSticks() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye(stick: .right)]))
        _ = e.handle(.gamepadStick(.right, x: 1, y: 0), at: 0)
        _ = e.tick(at: 0.016)
        _ = e.tick(at: 0.032)
        _ = e.reset()
        var after: [TouchEvent] = []
        for i in 1...10 { after += e.tick(at: 0.032 + Double(i) * 0.016) }
        #expect(after.isEmpty, "\(summary(after).prefix(3))")
    }

    /// A resize while aiming keeps the mouse locked, the eye's finger down on the new size.
    @Test func aResizeWhileAimingKeepsAiming() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye()], fps: FPSSettings(aimControl: "eye")))
        _ = e.setPointerLocked(true)
        let resized = summary(e.resize(width: 1920, height: 1080))
        #expect(resized == ["up[0] 0@1800,432", "down[0] 0@1440,432"])
        #expect(e.pointerLocked)
        #expect(e.handle(.mouseMoved(dx: 10, dy: 0), at: 0.1).consumed)
    }

    /// With the mouse locked, a click no control takes touches nothing at
    /// the parked cursor, and its release is taken too.
    @Test func anUnboundClickWhileAimingTouchesNothing() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye()], fps: FPSSettings(aimControl: "eye")))
        _ = e.setPointerLocked(true)
        #expect(!e.handle(.mouseDown(.left), at: 0).consumed)
        let down = e.handle(.fingerDown(x: 1200, y: 540), at: 0)
        #expect(down.consumed && down.events.isEmpty)
        let up = e.handle(.fingerUp(x: 1200, y: 540), at: 0.1)
        #expect(up.consumed && up.events.isEmpty)
        #expect(e.activeTouchCount == 1, "the eye's finger")
    }

    /// Two joysticks on WASD, one for each way the mouse is: as the mouse
    /// locks, the locked one's takes the keys still held.
    @Test func lockingTheMouseGivesItsJoystickTheKeysHeld() {
        let steer = Control(id: "steer", kind: .dpad(center: NormalizedPoint(0.3, 0.7), radius: 0.12, up: .key(.w), down: .key(.s),
                                                     left: .key(.a), right: .key(.d), stick: nil), layer: .locked)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye(), walk(layer: .cursor), steer], fps: FPSSettings(aimControl: "eye")))
        _ = e.handle(.keyDown(.w), at: 0)
        #expect(e.activeTouchCount == 1, "the free mouse's joystick")
        let locked = summary(e.setPointerLocked(true))
        #expect(e.activeTouchCount == 2, "the eye's finger and the locked mouse's joystick: \(locked)")
        #expect(locked.contains { $0.hasPrefix("pointerDown") && $0.contains("@720,") }, "\(locked)")
    }

    /// Aim Down Sights toggled on stays on when the mouse is freed (the game
    /// still aims down sights), so the next press turns it off.
    @Test func aToggledAimDownSightsStaysOnWhenTheMouseIsFreed() {
        let ads = Control(id: "ads", kind: .ads(NormalizedPoint(0.9, 0.5), toggle: true), triggers: [.key(.q)])
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye(), ads], fps: FPSSettings(aimControl: "eye")))
        _ = e.setPointerLocked(true)
        _ = e.handle(.keyDown(.q), at: 0)
        #expect(e.adsActive)
        _ = e.setPointerLocked(false)
        #expect(e.adsActive)
        _ = e.handle(.keyUp(.q), at: 0.1)
        _ = e.handle(.keyDown(.q), at: 0.2)
        #expect(!e.adsActive)
    }

    // MARK: Layouts

    /// Avo before actions: one key frees the mouse while it is locked and
    /// locks it while it is free (two mouse_look controls of two layers). It stays a toggle.
    @Test func layeredLegacyMouseLookStaysAToggle() throws {
        let profile = try KeymapProfile.decode(Data("""
        {"schema": 1, "package": "x", "name": "x",
         "fps": {"aim_control": "eye", "cursor_toggle": "key:F8"},
         "controls": [
           {"type": "aim", "id": "eye", "area": [0.5, 0.1, 1, 0.7]},
           {"type": "mouse_look", "id": "free", "lock": false, "triggers": ["key:M"], "layer": "locked"},
           {"type": "mouse_look", "id": "lock", "lock": true, "triggers": ["key:M"], "layer": "cursor"}
         ]}
        """.utf8))
        #expect(profile.validate().isEmpty)
        var e = engine(profile)
        _ = e.setPointerLocked(true)
        _ = e.handle(.keyDown(.m), at: 0)
        _ = e.handle(.keyUp(.m), at: 0.05)
        #expect(!e.pointerLocked)
        _ = e.handle(.keyDown(.m), at: 0.2)
        #expect(e.pointerLocked)
    }

    /// A hotkey whose only action a newer Avo wrote is left out (as a kind
    /// this version does not know), and the rest of the layout loads.
    @Test func aHotkeyThatOnlyANewerAvoUnderstandsIsLeftOut() throws {
        let profile = try KeymapProfile.decode(Data("""
        {"schema": 1, "package": "x", "name": "x",
         "controls": [
           {"type": "tap", "id": "jump", "position": [0.9, 0.7], "triggers": ["key:Space"]},
           {"type": "hotkey", "id": "h", "triggers": ["key:H"], "actions": [{"camera": "recenter"}]},
           {"type": "hotkey", "id": "both", "triggers": ["key:G"], "actions": [{"camera": "recenter"}, {"mouse": "toggle"}]},
           {"type": "hotkey", "id": "new", "triggers": ["key:N"]}
         ]}
        """.utf8))
        #expect(profile.controls.map(\.id) == ["jump", "both", "new"])
        #expect(profile.controls[1].actions == [.toggleMouse])
        #expect(profile.unsupportedControls == ["hotkey"])
        #expect(profile.validate().contains("new: does nothing yet: add an action"), "a hotkey still being set up is still refused")
    }

    /// A size from Avo before b64 is kept as it is, whatever it was: it changes nothing.
    @Test func anOldButtonSizeOutOfRangeStillLoads() throws {
        let profile = try KeymapProfile.decode(Data("""
        {"schema": 1, "package": "x", "name": "x",
         "controls": [{"type": "tap", "id": "jump", "position": [0.9, 0.7], "triggers": ["key:Space"], "size": 0.9}]}
        """.utf8))
        #expect(profile.validate().isEmpty)
        #expect(profile.controls[0].size == 0.9)
    }

    @Test func theMouseLockCannotBeTheWheel() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [eye()], fps: FPSSettings(cursorToggle: .scrollUp, aimControl: "eye"))
        #expect(profile.validate() == ["the wheel cannot lock and free the mouse"])
    }

    /// A preset that leaves out a control only the controller pressed keeps
    /// its buttons on it: with none, the layout could not be saved.
    @Test func applyingAPresetKeepsTheLayoutValid() {
        var profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "jump", kind: .tap(NormalizedPoint(0.9, 0.7)), triggers: [.key(.space), .gamepad(.b)]),
            Control(id: "pad-only", kind: .tap(NormalizedPoint(0.8, 0.7)), triggers: [.gamepad(.y)]),
        ])
        profile.apply(GamepadPreset(name: "p", bindings: ["jump": GamepadBinding(buttons: [.a])]))
        #expect(profile.validate().isEmpty, "\(profile.validate())")
        #expect(profile.controls[0].triggers == [.key(.space), .gamepad(.a)], "the preset's own")
        #expect(profile.controls[1].triggers == [.gamepad(.y)], "kept")
    }

    /// "Replace Layout" with a template leaves the old layout's modes behind too.
    @Test func replacingWithATemplateLeavesNoModes() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "drive", kind: .hotkey, triggers: [.key(.v)], modes: ["foot"], actions: [.switchMode("car")]),
        ], modes: [KeymapMode(id: "foot", name: "Foot"), KeymapMode(id: "car", name: "Car")])
        let replaced = KeymapTemplate.fps.insert(into: profile, replacing: true, aspect: 16.0 / 9).profile
        #expect(replaced.modes.isEmpty)
        #expect(replaced.controls.allSatisfy { $0.modes == nil })
        #expect(replaced.validate().isEmpty, "\(replaced.validate())")
    }
}
