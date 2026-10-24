import AppKit
import AvoHazeUI
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

// The editor's menus offer what the control takes, under the names the
// panel uses, in real sections.

private func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .avoSharedKit) }

private func titles(_ entries: [HazeMenuEntry]) -> [String] {
    entries.compactMap { entry in
        switch entry {
        case .item(let item): item.title
        case .section(let title, _): "§" + title
        default: nil
        }
    }
}

private let eye = Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                                adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: nil,
                                                origin: NormalizedPoint(0.8, 0.5)))

@MainActor
@Suite("The key mapping editor's menus")
struct KeymapEditorMenuTests {
    @Test("Right-click offers each control only the keys it takes")
    func rightClickOffersWhatFits() {
        let controls = [
            Control(id: "tap", kind: .tap(NormalizedPoint(0.1, 0.1)), triggers: [.key(.t)]),
            Control(id: "anchor", kind: .anchor(NormalizedPoint(0.2, 0.2), radius: 0.18), triggers: [.key(.e)]),
            Control(id: "area", kind: .clickArea(NormalizedRect(0.8, 0, 0.9, 0.1), passThrough: true), actions: [.lockMouse]),
            Control(id: "move", kind: .dpad(center: NormalizedPoint(0.15, 0.7), radius: 0.12, up: .key(.w), down: .key(.s), left: .key(.a),
                                            right: .key(.d), stick: nil)),
            eye,
        ]
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: controls, fps: FPSSettings(aimControl: "eye")))
        defer { editor.close() }
        let wheel = L("Wheel Up"), left = L("Left Click"), esc = L("Esc Key")
        let tap = titles(editor.view.contextEntries(for: "tap"))
        #expect(tap.contains(wheel) && tap.contains(left) && tap.contains(esc) && tap.contains(L("Add Action")))
        let anchor = titles(editor.view.contextEntries(for: "anchor"))
        #expect(!anchor.contains(wheel) && anchor.contains(left))
        #expect(anchor.contains("§" + L("Finger reach")) && anchor.contains(L("In a Circle")) && anchor.contains(L("Whole Screen")))
        let area = titles(editor.view.contextEntries(for: "area"))
        #expect(!area.contains(wheel) && !area.contains(left) && !area.contains(esc))
        let move = titles(editor.view.contextEntries(for: "move"))
        #expect(!move.contains(wheel) && !move.contains(left), "a joystick's keys are set in the panel")
        let eyeMenu = titles(editor.view.contextEntries(for: "eye"))
        #expect(eyeMenu.contains("§" + L("Mouse lock key")) && !eyeMenu.contains(wheel) && !eyeMenu.contains(left))
        #expect(eyeMenu.contains("§" + L("Swipe area")) && eyeMenu.contains(L("Full Height")) && eyeMenu.contains(L("Right Side"))
            && eyeMenu.contains(L("Touch in the Middle")))
        #expect(eyeMenu.last == L("Remove"))
    }

    @Test("The wheel never becomes a joystick's direction")
    func noWheelOnAJoystick() {
        let move = Control(id: "move", kind: .dpad(center: NormalizedPoint(0.15, 0.7), radius: 0.12, up: .key(.w), down: .key(.s),
                                                   left: .key(.a), right: .key(.d), stick: nil))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [move]))
        defer { editor.close() }
        editor.model.select("move")
        editor.view.assign(.scrollUp)
        #expect(editor.profile.controls[0].kind == move.kind)
        #expect(editor.model.problem)
    }

    @Test("Works In ticks a control's modes from its menu")
    func worksInFromTheMenu() throws {
        let tap = Control(id: "tap", kind: .tap(NormalizedPoint(0.1, 0.1)), triggers: [.key(.t)], modes: ["a"])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap],
                                          modes: [KeymapMode(id: "a", name: "On foot"), KeymapMode(id: "b", name: "Car")]))
        defer { editor.close() }
        editor.model.select("tap")
        let car = try #require(editor.item("Car", in: editor.view.contextEntries(for: "tap")))
        #expect(car.state == .off)
        car.action()
        #expect(editor.profile.controls[0].modes == ["a", "b"])
        let every = try #require(editor.item(L("Every Mode"), in: editor.view.contextEntries(for: "tap")))
        every.action()
        #expect(editor.profile.controls[0].modes == nil)
    }

    @Test("The controller's placement menu has sections, the stick's press its own")
    func placementSections() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: []))
        defer { editor.close() }
        let button = editor.view.placementEntries(for: .button(.a), at: NormalizedPoint(0.5, 0.5))
        let general = L("General"), fps = L("FPS")
        #expect(titles(button).first == "§" + general)
        #expect(titles(button).contains("§" + fps))
        // The stick's own choices first (a joystick under General, the eye under FPS), then its press's under their own title.
        let stick = titles(editor.view.placementEntries(for: .stick(.left), at: NormalizedPoint(0.5, 0.5)))
        let pressing = "§" + L("Pressing it down (\("•"))").prefix { $0 != "(" }
        #expect(stick.first == "§" + general)
        #expect(stick.contains { $0.hasPrefix(pressing) }, "\(stick)")
        // Choosing one places it.
        if case .item(let tap)? = button.first(where: { if case .item(let item) = $0 { item.title == L("Tap") } else { false } }) {
            tap.action()
        }
        #expect(editor.profile.controls.count == 1)
        #expect(editor.profile.controls.first?.triggers == [.gamepad(.a)])
    }
}
