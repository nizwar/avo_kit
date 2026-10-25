import AppKit
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

// A controller preset that takes a control's only buttons says which
// controls it left without a key; one that had none before is no news.

private func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .avoSharedKit) }

@MainActor
@Suite("The controller panel's presets")
struct KeymapEditorPresetTests {
    private let move = Control(id: "move", kind: .dpad(center: NormalizedPoint(0.15, 0.7), radius: 0.12, up: .key(.w), down: .key(.s),
                                                       left: .key(.a), right: .key(.d), stick: nil))
    private let preset = GamepadPreset(name: "p", bindings: ["move": GamepadBinding(dpad: true)])

    private func apply(_ name: String, in editor: Editor) throws {
        let panel = try #require(Mirror(reflecting: editor.view).descendant("controllerPanel") as? ControllerPanelModel)
        panel.applyPreset(name)
    }

    @Test("A preset giving the d-pad to a joystick names the taps that had only its buttons, once")
    func aPresetNamesWhatItLeftWithoutAKey() throws {
        let up = Control(id: "up", kind: .tap(NormalizedPoint(0.5, 0.2)), triggers: [.gamepad(.dpadUp)])
        let left = Control(id: "left", kind: .tap(NormalizedPoint(0.4, 0.2)), triggers: [.gamepad(.dpadLeft)])
        let both = Control(id: "both", kind: .tap(NormalizedPoint(0.6, 0.2)), triggers: [.key(.t), .gamepad(.dpadDown)])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [move, up, left, both],
                                          gamepad: GamepadSettings(presets: [preset])))
        defer { editor.close() }
        try apply("p", in: editor)
        let triggers = Dictionary(uniqueKeysWithValues: editor.profile.controls.map { ($0.id, $0.triggers) })
        #expect(triggers["up"] == [] && triggers["left"] == [] && triggers["both"] == [.key(.t)])
        let tap = "“\(L("Tap"))”"
        #expect(editor.model.status.hasSuffix(L("Left without a key: \(tap). Select each “?” and press a key.")), "\(editor.model.status)")
        #expect(editor.model.problem)
    }

    @Test("A control that had no key before the preset is not named")
    func onlyNewsIsNamed() throws {
        let keyless = Control(id: "k", kind: .tap(NormalizedPoint(0.5, 0.2)))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [move, keyless], gamepad: GamepadSettings(presets: [preset])))
        defer { editor.close() }
        try apply("p", in: editor)
        #expect(editor.model.status == L("Using the preset “\("p")”."))
        #expect(!editor.model.problem)
    }
}
