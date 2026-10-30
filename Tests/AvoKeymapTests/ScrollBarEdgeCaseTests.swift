import AvoInput
import Foundation
import Testing
@testable import AvoKeymap

// The scroll bar where play gets in the way: focus lost, the window
// resized, the mouse locked or the mode switched while the wheel's finger
// is down; many notches at once; the eye's area; a layout saved mid-game.

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

/// "0@2160,511" of "up[0] 0@2160,511".
private func spot(_ line: String?) -> String? { line?.split(separator: " ").last.map(String.init) }

private func isDown(_ line: String) -> Bool { line.hasPrefix("down") || line.hasPrefix("pointerDown") }

/// The map's zoom slider: bottom (y 0.8) to top (y 0.2), resting halfway, a
/// tenth a notch. On 2400 x 1080: x 2160, rest y 540, a step up y 475, the top y 216.
private func zoom(reset: Trigger? = nil, modes: [String]? = nil, layer: ControlLayer? = nil) -> Control {
    Control(id: "zoom", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1),
            layer: layer, modes: modes, reset: reset)
}

/// An eye on the left of the screen, away from the zoom slider.
private func eye(area: NormalizedRect = NormalizedRect(0.1, 0.1, 0.6, 0.7)) -> Control {
    Control(id: "eye", kind: .aim(area: area, sensitivity: AxisPair(x: 1, y: 1), adsSensitivity: AxisPair(x: 1, y: 1),
                                  exponent: 1, deadzone: 0, invertY: false, stick: nil))
}

@Suite struct ScrollBarEdgeCaseTests {
    // MARK: The thumb's place

    /// Focus lost right after a notch: the finger goes the rest of the way
    /// before it lifts, so the next notch touches the thumb where the game has it.
    @Test func focusLostMidGlideLetsGoWhereTheThumbIs() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [zoom()]))
        _ = e.handle(.scroll(dy: 1), at: 0)
        let lifted = summary(e.reset())
        #expect(lifted == ["move[0] 0@2160,475", "up[0] 0@2160,475"])
        let next = summary(e.handle(.scroll(dy: 1), at: 1).events)
        #expect(next.first == "down[0] 0@2160,475")
    }

    /// The same when the window is resized mid-scroll.
    @Test func aResizeMidGlideLetsGoWhereTheThumbIs() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [zoom()]))
        _ = e.handle(.scroll(dy: 1), at: 0)
        let lifted = summary(e.resize(width: W, height: H))
        let next = summary(e.handle(.scroll(dy: 1), at: 1).events)
        #expect(spot(lifted.last) == "0@2160,475")
        #expect(spot(next.first) == "0@2160,475")
    }

    /// A scroll bar of the cursor's layer whose finger is down when the
    /// mouse locks: it lets go where the thumb was dragged to.
    @Test func lockingTheMouseMidGlideLetsGoWhereTheThumbIs() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [eye(), zoom(layer: .cursor)], fps: FPSSettings(aimControl: "eye")))
        _ = e.handle(.scroll(dy: 1), at: 0)
        let locked = summary(e.setPointerLocked(true))
        let up = locked.first { $0.hasPrefix("up") || $0.hasPrefix("pointerUp") }
        #expect(spot(up) == "0@2160,475", "\(locked)")
        _ = e.setPointerLocked(false)
        let next = summary(e.handle(.scroll(dy: 1), at: 1).events)
        #expect(spot(next.first) == "0@2160,475", "\(next)")
    }

    /// A mode switch while the wheel's finger is down, on a scroll bar of
    /// both modes: the bar goes back to rest, its finger lets go, and the
    /// next notch touches the thumb at rest.
    @Test func aModeSwitchLetsGoOfTheWheelsFinger() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            zoom(),
            Control(id: "drive", kind: .hotkey, triggers: [.key(.v)], modes: ["map"], actions: [.switchMode("car")]),
        ], modes: [KeymapMode(id: "map", name: "Map"), KeymapMode(id: "car", name: "Car")])
        #expect(profile.validate().isEmpty)
        var e = engine(profile)
        _ = e.handle(.scroll(dy: 1), at: 0)
        _ = e.tick(at: 0.02)
        let switched = summary(e.handle(.keyDown(.v), at: 0.05).events)
        #expect(e.mode == "car")
        #expect(switched.last == "up[0] 0@2160,475", "\(switched)")
        #expect(e.activeTouchCount == 0)
        let next = summary(e.handle(.scroll(dy: 1), at: 0.1).events)
        #expect(next.first == "down[0] 0@2160,540", "\(next)")
    }

    @Test func manyFastNotchesKeepOneFingerAndStopAtTheEnd() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [zoom()]))
        var all: [String] = []
        for i in 0..<20 {
            all += summary(e.handle(.scroll(dy: 1), at: Double(i) * 0.01).events)
            all += summary(e.tick(at: Double(i) * 0.01 + 0.005))
        }
        #expect(all.filter(isDown).count == 1)
        all += summary(e.tick(at: 0.3) + e.tick(at: 0.5))
        #expect(all.last == "up[0] 0@2160,216", "\(all.suffix(3))")
        #expect(e.activeTouchCount == 0)
    }

    @Test func turningTheWheelBackMidGlideComesBackToRest() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [zoom()]))
        _ = e.handle(.scroll(dy: 1), at: 0)
        _ = e.handle(.scroll(dy: -1), at: 0.01)
        let rest = summary(e.tick(at: 0.05) + e.tick(at: 0.1) + e.tick(at: 0.3))
        #expect(rest.last == "up[0] 0@2160,540", "\(rest)")
    }

    @Test func theResetKeyWhileTheWheelsFingerIsDownUsesTheSameFinger() {
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [zoom(reset: .key(.z))]))
        _ = e.handle(.scroll(dy: 1), at: 0)
        let reset = summary(e.handle(.keyDown(.z), at: 0.05).events)
        #expect(!reset.contains(where: isDown), "\(reset)")
        _ = e.handle(.keyUp(.z), at: 0.06)
        let after = summary(e.tick(at: 0.1) + e.tick(at: 0.26) + e.tick(at: 0.31))
        #expect(after.last == "up[0] 0@2160,540", "\(after)")
    }

    /// Every finger taken (16 holds): the notch does nothing, and the thumb
    /// is still believed at rest.
    @Test func withNoFingerFreeTheThumbStaysWhereItWas() {
        let keys: [KeyName] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p]
        let holds = keys.enumerated().map { i, key in
            Control(id: "h\(i)", kind: .hold(NormalizedPoint(0.05 + 0.05 * Double(i), 0.1)), triggers: [.key(key)])
        }
        var e = engine(KeymapProfile(package: "x", name: "x", controls: holds + [zoom()]))
        for key in keys { _ = e.handle(.keyDown(key), at: 0) }
        #expect(e.activeTouchCount == 16)
        #expect(e.handle(.scroll(dy: 1), at: 0.1).events.isEmpty)
        _ = e.handle(.keyUp(.a), at: 0.2)
        let next = summary(e.handle(.scroll(dy: 1), at: 0.3).events)
        #expect(spot(next.first) == "0@2160,540", "\(next)")
    }

    @Test func anotherControlOnTheWheelActsToo() {
        let tap = Control(id: "weapon", kind: .tap(NormalizedPoint(0.5, 0.9)), triggers: [.scrollUp])
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [zoom(), tap]))
        #expect(e.handle(.scroll(dy: 1), at: 0).consumed)
        #expect(e.activeTouchCount == 2)
        _ = e.tick(at: 0.1)
        #expect(e.activeTouchCount == 1, "the tap lifted, the bar's finger stays")
    }

    @Test func aScrollBarOfAnotherModeLeavesTheWheelToTheGame() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [zoom(modes: ["map"])],
                                    modes: [KeymapMode(id: "foot", name: "Foot"), KeymapMode(id: "map", name: "Map")])
        var e = engine(profile)
        #expect(!e.takes(.scrollUp) && !e.takes(.scrollDown))
        let out = e.handle(.scroll(dy: 1), at: 0)
        #expect(!out.consumed)
        #expect(out.events.isEmpty)
    }

    // MARK: The eye's area

    /// Over the eye's swipe area, in a mode the eye works in, a scroll bar is
    /// refused as a swipe there is: its drag would turn the camera, whether
    /// the mouse aims or a key fires with it free (no recoil compensation).
    /// A map's slider there gets a mode without the eye.
    @Test func aScrollBarOverTheAimAreaIsRefusedWhereTheEyeWorks() {
        let pull = Control(id: "pull", kind: .scrollBar(from: NormalizedPoint(0.3, 0.3), to: NormalizedPoint(0.3, 0.6), rest: 0, step: 0.05))
        let refused = KeymapProfile(package: "x", name: "x", controls: [eye(), pull, zoom()], fps: FPSSettings(aimControl: "eye"))
        #expect(refused.scrollBarsOverTheAimArea == ["pull"])
        #expect(refused.validate() == ["pull: a scroll bar may not drag over the aim area where the eye works (no recoil compensation)"])
        // Only in the map's mode, where the eye does not work: allowed, and it
        // works there with the mouse locked or not.
        var eyeOnFoot = eye()
        eyeOnFoot.modes = ["foot"]
        var mapOnly = pull
        mapOnly.modes = ["map"]
        let toMap = Control(id: "toMap", kind: .hotkey, triggers: [.key(.m)], modes: ["foot"], actions: [.switchMode("map")])
        let modes = [KeymapMode(id: "foot", name: "Foot"), KeymapMode(id: "map", name: "Map")]
        let allowed = KeymapProfile(package: "x", name: "x", controls: [eyeOnFoot, mapOnly, toMap], fps: FPSSettings(aimControl: "eye"), modes: modes)
        #expect(allowed.scrollBarsOverTheAimArea.isEmpty)
        #expect(allowed.validate().isEmpty, "\(allowed.validate())")
        var e = engine(allowed)
        _ = e.setPointerLocked(true)
        #expect(!e.takes(.scrollUp), "on foot: no bar")
        #expect(e.handle(.keyDown(.m), at: 0).mode == "map")
        #expect(e.handle(.scroll(dy: 1), at: 0.1).consumed)
        // An eye of every mode works in the map's too: refused.
        let everyMode = KeymapProfile(package: "x", name: "x", controls: [eye(), mapOnly], fps: FPSSettings(aimControl: "eye"), modes: modes)
        #expect(everyMode.validate().contains { $0.hasPrefix("pull:") })
    }

    @Test func aTrackCrossingAnAreaTouchesIt() {
        let area = NormalizedRect(0.4, 0.2, 0.8, 0.6)
        func touches(_ a: (Double, Double), _ b: (Double, Double)) -> Bool {
            area.touches(from: NormalizedPoint(a.0, a.1), to: NormalizedPoint(b.0, b.1))
        }
        #expect(touches((0.5, 0.3), (0.6, 0.5)), "inside")
        #expect(touches((0.3, 0.4), (0.9, 0.4)), "across, both ends outside")
        #expect(touches((0.6, 0.1), (0.6, 0.7)), "up and down through it")
        #expect(touches((0.3, 0.4), (0.4, 0.4)), "ending on its edge")
        #expect(!touches((0.3, 0.7), (0.9, 0.7)), "below it")
        #expect(!touches((0.1, 0.1), (0.3, 0.7)), "beside it")
        #expect(!touches((0.3, 0.1), (0.5, 0.15)), "past its corner")
        #expect(touches((0.5, 0.4), (0.5, 0.4)), "a point inside")
        #expect(!touches((0.9, 0.9), (0.9, 0.9)), "a point outside")
    }

    // MARK: A layout saved mid-game

    /// The window's new engine for a saved layout carries on from the old
    /// one: in its mode, the thumbs where the game has them (but a bar whose
    /// track moved starts from rest).
    @Test func aNewEngineCarriesOnFromTheOldOne() {
        var profile = KeymapProfile(package: "x", name: "x", controls: [
            zoom(),
            Control(id: "drive", kind: .hotkey, triggers: [.key(.v)], modes: ["foot"], actions: [.switchMode("car")]),
        ], modes: [KeymapMode(id: "foot", name: "Foot"), KeymapMode(id: "car", name: "Car")])
        var e = engine(profile)
        _ = e.handle(.keyDown(.v), at: 0)
        _ = e.handle(.keyUp(.v), at: 0.01)
        _ = e.handle(.scroll(dy: 1), at: 1)
        _ = e.tick(at: 2)
        _ = e.reset()
        var next = KeymapEngine(profile: profile, displayID: 7, width: W, height: H, touchSpread: 0, continuing: e)
        #expect(next.mode == "car")
        #expect(summary(next.handle(.scroll(dy: 1), at: 3).events).first == "down[0] 0@2160,475")
        // The track moved, and the mode is gone.
        profile.controls[0].kind = .scrollBar(from: NormalizedPoint(0.8, 0.8), to: NormalizedPoint(0.8, 0.2), rest: 0.5, step: 0.1)
        profile.modes = [KeymapMode(id: "foot", name: "Foot")]
        var moved = KeymapEngine(profile: profile, displayID: 7, width: W, height: H, touchSpread: 0, continuing: e)
        #expect(moved.mode == "foot")
        #expect(summary(moved.handle(.scroll(dy: 1), at: 3).events).first == "down[0] 0@1920,540")
    }

    // MARK: Validation

    /// The editor's shortest horizontal track (a twentieth of the height
    /// long on the screen) saves, on a 20:9 screen and on a 32:9 one.
    @Test func theEditorsShortestHorizontalTrackSaves() {
        for aspect in [W / H, 32.0 / 9] {
            let length = Control.minimumScrollTrack / aspect
            let bar = Control(id: "h", kind: .scrollBar(from: NormalizedPoint(0.3, 0.5), to: NormalizedPoint(0.3 + length, 0.5), rest: 0.5, step: 0.1))
            let problems = KeymapProfile(package: "x", name: "x", controls: [bar]).validate()
            #expect(problems.isEmpty, "\(aspect): \(problems)")
        }
    }

    @Test func validationEdges() throws {
        func problems(_ kind: Control.Kind, reset: Trigger? = nil, actions: [ControlAction] = []) -> [String] {
            KeymapProfile(package: "x", name: "x", controls: [Control(id: "s", kind: kind, actions: actions, reset: reset)],
                          modes: [KeymapMode(id: "a", name: "A")]).validate()
        }
        let a = NormalizedPoint(0.9, 0.8), b = NormalizedPoint(0.9, 0.2)
        #expect(problems(.scrollBar(from: a, to: b, rest: 0, step: 0.1)).isEmpty)
        #expect(problems(.scrollBar(from: a, to: b, rest: 1, step: 0.1)).isEmpty)
        #expect(problems(.scrollBar(from: a, to: b, rest: 0.5, step: 0.01)).isEmpty)
        #expect(problems(.scrollBar(from: a, to: b, rest: 0.5, step: 0.5)).isEmpty)
        #expect(!problems(.scrollBar(from: a, to: b, rest: 0.5, step: 0.0099)).isEmpty)
        #expect(!problems(.scrollBar(from: a, to: b, rest: 0.5, step: 0.51)).isEmpty)
        #expect(!problems(.scrollBar(from: a, to: a, rest: 0.5, step: 0.1)).isEmpty)
        #expect(!problems(.scrollBar(from: a, to: b, rest: .nan, step: 0.1)).isEmpty)
        #expect(!problems(.scrollBar(from: a, to: b, rest: 0.5, step: 0.1), reset: .scrollDown).isEmpty)
        #expect(problems(.scrollBar(from: a, to: b, rest: 0.5, step: 0.1), actions: [.switchMode("a")])
            == ["s: this kind of control cannot do actions"])
        // Right to left: wheel up drags it left.
        let rtl = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.8, 0.5), to: NormalizedPoint(0.2, 0.5), rest: 0.5, step: 0.1))
        #expect(KeymapProfile(package: "x", name: "x", controls: [rtl]).validate().isEmpty)
        var e = engine(KeymapProfile(package: "x", name: "x", controls: [rtl]))
        _ = e.handle(.scroll(dy: 1), at: 0)
        #expect(summary(e.tick(at: 0.1) + e.tick(at: 0.3)).last == "up[0] 0@1056,540")
        // Unknown fields and a reset this version cannot read: the bar still loads.
        let json = Data("""
        {"schema": 1, "package": "x", "name": "x", "controls": [
          {"type": "scroll_bar", "id": "z", "from": [0.9, 0.8], "to": [0.9, 0.2], "reset": "key:Nope", "glow": true}
        ]}
        """.utf8)
        let decoded = try KeymapProfile.decode(json)
        #expect(decoded.controls.first?.reset == nil)
        #expect(decoded.controls.first?.kind == .scrollBar(from: a, to: b, rest: Control.defaultScrollRest, step: Control.defaultScrollStep))
    }
}
