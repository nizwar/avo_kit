import AvoInput
import Foundation
import Testing
@testable import AvoKeymap

// The layouts of Avo before actions (Switch Mode and Free/Lock the Mouse
// controls), the controller's part of a layout with the new controls, and a
// layout from a newer Avo.

private let W = 2400.0, H = 1080.0

private func engine(_ profile: KeymapProfile) -> KeymapEngine {
    KeymapEngine(profile: profile, displayID: 7, width: W, height: H, touchSpread: 0)
}

private func json(_ controls: String) -> Data {
    Data("""
    {"schema": 1, "package": "x", "name": "x",
     "fps": {"aim_control": "eye", "cursor_toggle": "key:F8"},
     "modes": [{"id": "foot", "name": "On foot"}, {"id": "vehicle", "name": "Vehicle"}],
     "controls": [
       {"type": "aim", "id": "eye", "area": [0.5, 0.1, 1, 0.7]},
       \(controls)
     ]}
    """.utf8)
}

private func zoom(reset: Trigger? = nil) -> Control {
    Control(id: "zoom", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1), reset: reset)
}

@Suite struct LegacyAndControllerEdgeCaseTests {
    // MARK: Layouts of Avo before actions

    /// A Switch Mode of the locked mouse's layer on the key of the game's
    /// button stays a hotkey of its own: with the mouse free, F only presses
    /// the button, as it did.
    @Test func aLegacySwitchKeepsItsLayer() throws {
        let profile = try KeymapProfile.decode(json("""
            {"type": "tap", "id": "enter", "position": [0.8, 0.6], "triggers": ["key:F"], "modes": ["foot"]},
            {"type": "switch_mode", "id": "drive", "mode": "vehicle", "triggers": ["key:F"], "modes": ["foot"], "layer": "locked"}
            """))
        #expect(profile.validate().isEmpty)
        #expect(profile.controls.map(\.id) == ["eye", "enter", "drive"])
        var e = engine(profile)
        #expect(e.handle(.keyDown(.f), at: 0).mode == nil, "the mouse is free")
        _ = e.handle(.keyUp(.f), at: 0.1)
        _ = e.setPointerLocked(true)
        #expect(e.handle(.keyDown(.f), at: 1).mode == "vehicle")
    }

    /// A legacy control with a click zone keeps it, as a hotkey of its own.
    @Test func aLegacyControlKeepsItsClickZone() throws {
        let profile = try KeymapProfile.decode(json("""
            {"type": "tap", "id": "enter", "position": [0.8, 0.6], "triggers": ["key:F"], "modes": ["foot"]},
            {"type": "switch_mode", "id": "drive", "mode": "vehicle", "triggers": ["key:F"], "modes": ["foot"],
             "click_zone": {"area": [0.8, 0.5, 0.9, 0.7]}}
            """))
        let drive = try #require(profile.controls.first { $0.id == "drive" })
        #expect(drive.kind == .hotkey)
        #expect(drive.clickZone?.area == NormalizedRect(0.8, 0.5, 0.9, 0.7))
        #expect(profile.controls.first { $0.id == "enter" }?.actions == [])
        #expect(profile.validate().isEmpty)
    }

    @Test func aLegacyMouseLookWithoutLockFreesAndTheOrderIsKept() throws {
        let profile = try KeymapProfile.decode(json("""
            {"type": "mouse_look", "id": "free", "triggers": ["key:G"]},
            {"type": "tap", "id": "bag", "position": [0.1, 0.1], "triggers": ["key:G"]},
            {"type": "switch_mode", "id": "drive", "mode": "vehicle", "triggers": ["key:G"]}
            """))
        #expect(profile.controls.map(\.id) == ["eye", "bag"])
        #expect(profile.controls[1].actions == [.freeMouse, .switchMode("vehicle")])
    }

    // MARK: The controller

    /// A scroll bar whose reset key is a controller button: unbinding the
    /// button, or taking the controller off the layout, takes it off the bar too.
    @Test func unbindingAControllerButtonTakesItOffAScrollBarsReset() {
        var profile = KeymapProfile(package: "x", name: "x", controls: [zoom(reset: .gamepad(.y))])
        #expect(profile.validate().isEmpty)
        #expect(profile.boundGamepadElements.contains(.button(.y)))
        profile.unbind(.button(.y))
        #expect(profile.controls[0].reset == nil)
        #expect(profile.controls(boundTo: .button(.y)).isEmpty)
        var removed = KeymapProfile(package: "x", name: "x", controls: [zoom(reset: .gamepad(.y))])
        #expect(removed.removeGamepadMapping().isEmpty, "the wheel still works it")
        #expect(removed.controls.map(\.id) == ["zoom"])
        #expect(removed.controls[0].reset == nil)
        // A key stays.
        var keyed = KeymapProfile(package: "x", name: "x", controls: [zoom(reset: .key(.z))])
        keyed.removeGamepadMapping()
        #expect(keyed.controls[0].reset == .key(.z))
    }

    /// "Reset the controller mapping" keeps a control on a controller
    /// button that a click on its zone also presses (it loses the button).
    @Test func resettingTheControllerMappingKeepsAControlItsZonePresses() {
        var profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "shop", kind: .tap(NormalizedPoint(0.1, 0.1)), triggers: [.gamepad(.y)],
                    clickZone: ClickZone(area: NormalizedRect(0.05, 0.05, 0.15, 0.15))),
        ])
        #expect(profile.validate().isEmpty)
        #expect(profile.controllerOnlyControls.isEmpty)
        profile.removeGamepadMapping()
        #expect(profile.controls.map(\.id) == ["shop"])
        #expect(profile.controls[0].triggers.isEmpty)
        #expect(profile.controls[0].clickZone != nil)
    }

    // MARK: Actions and hotkeys

    @Test func aHotkeyOnTheWheelSwitchesAndTheScrollBarOfTheOldModeLetsGo() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "zoom", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1),
                    modes: ["map"]),
            Control(id: "out", kind: .hotkey, triggers: [.scrollDown], modes: ["map"], actions: [.switchMode("foot")]),
        ], modes: [KeymapMode(id: "map", name: "Map"), KeymapMode(id: "foot", name: "Foot")])
        #expect(profile.validate().isEmpty)
        var e = engine(profile)
        let out = e.handle(.scroll(dy: -1), at: 0)
        #expect(out.mode == "foot")
        #expect(e.activeTouchCount == 0, "the bar of the map lifted with the switch")
    }

    /// The mouse lock's key and a hotkey on it that toggles the mouse too
    /// cancel out: both toggle. Not something the engine can know better.
    @Test func aTogglingHotkeyOnTheMouseLocksKeyCancelsItOut() {
        let profile = KeymapProfile(package: "x", name: "x", controls: [
            Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                          adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: nil)),
            Control(id: "t", kind: .hotkey, triggers: [.key(.f8)], actions: [.toggleMouse]),
        ], fps: FPSSettings(aimControl: "eye"))
        #expect(profile.validate().isEmpty)
        var e = engine(profile)
        _ = e.handle(.keyDown(.f8), at: 0)
        #expect(!e.pointerLocked)
    }

    // MARK: Reading a layout

    /// A zone on a kind this version cannot click (a newer Avo may) is left
    /// out as the file is read: the layout still loads.
    @Test func aZoneOnAKindThatCannotBeClickedIsLeftOutOfAFile() throws {
        let json = Data("""
        {"schema": 1, "package": "x", "name": "x", "controls": [
          {"type": "dpad", "id": "move", "center": [0.2, 0.7], "radius": 0.1, "click_zone": {"area": [0.1, 0.6, 0.3, 0.8]}},
          {"type": "scroll_bar", "id": "zoom", "from": [0.9, 0.8], "to": [0.9, 0.2], "click_zone": {"area": [0.85, 0.2, 0.95, 0.8]}}
        ]}
        """.utf8)
        let profile = try KeymapProfile.decode(json)
        #expect(profile.controls.allSatisfy { $0.clickZone == nil })
        #expect(profile.validate().isEmpty)
    }
}
