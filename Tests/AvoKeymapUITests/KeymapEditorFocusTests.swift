import AppKit
import AvoHazeUI
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

// Where the keyboard goes while the editor is open: a mode's name typed in
// the panel, a question over the game, the pointer leaving the editor, a
// drag from the panel that SwiftUI drops.

private func tap(_ id: String = "t") -> Control { Control(id: id, kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.t)]) }

private func isNil(_ value: Any?) -> Bool {
    guard let value else { return true }
    let mirror = Mirror(reflecting: value)
    return mirror.displayStyle == .optional && mirror.children.isEmpty
}

@MainActor
@Suite("Where the editor's keys go")
struct KeymapEditorFocusTests {
    @Test("A mode's name typed in its tab is kept when a control is added from the panel, and the next key is the control's")
    func aNameIsKeptWhenThePanelIsUsed() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.model.addMode()
        let id = editor.model.renaming
        #expect(id != nil)
        editor.model.renamingText = "Vehicle"
        editor.model.add(.tap)
        #expect(editor.model.renaming == nil)
        #expect(editor.profile.modes.first { $0.id == id }?.name == "Vehicle")
        editor.press(MacKey.f, "f")
        #expect(editor.profile.controls.last?.triggers == [.key(.f)], "the F went to the new tap, not into the name")
    }

    @Test("A click or a key on the game keeps the name typed so far; Esc in the field keeps the old one")
    func aClickOrAKeyKeepsTheName() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: []))
        defer { editor.close() }
        editor.model.addMode()
        let first = editor.model.renaming
        editor.model.renamingText = "Car"
        editor.click(0.3, 0.3)
        #expect(editor.profile.modes.first { $0.id == first }?.name == "Car")
        editor.model.addMode()
        let second = editor.model.renaming
        editor.model.renamingText = "Boat"
        editor.press(MacKey.f, "f")
        #expect(editor.profile.modes.first { $0.id == second }?.name == "Boat")
        // Esc in the field: the name stays as it was.
        editor.model.addMode()
        let third = editor.model.renaming!
        let before = editor.profile.modes.first { $0.id == third }?.name
        editor.model.renamingText = "Plane"
        editor.model.rename(third, nil)
        #expect(editor.profile.modes.first { $0.id == third }?.name == before)
    }

    @Test("While a question is up the panel's Done and Cancel wait")
    func donWaitsForAQuestion() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.model.sheetUp = true
        editor.model.done()
        #expect(editor.saved.profile == nil)
        editor.model.sheetUp = false
        editor.model.done()
        #expect(editor.saved.profile != nil)
    }

    @Test("Leaving the editor lets go of the hovered control")
    func hoverGoesWithThePointer() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        let over = NSEvent.mouseEvent(with: .mouseMoved, location: editor.point(0.5, 0.5), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.window.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 0, pressure: 0)!
        editor.view.mouseMoved(with: over)
        #expect(!isNil(Mirror(reflecting: editor.view).descendant("hovered")))
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: editor.point(1.2, 0.5), modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.window.windowNumber, context: nil,
                                          eventNumber: 0, trackingNumber: 0, userData: nil)!
        editor.view.mouseExited(with: exit)
        #expect(isNil(Mirror(reflecting: editor.view).descendant("hovered")))
    }

    @Test("A drag from the panel that is dropped takes its ghost with it and places nothing")
    func aDroppedDragLeavesNoGhost() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: []))
        defer { editor.close() }
        editor.model.drag(.tap, .moved, CGPoint(x: 600, y: 270))
        #expect(!isNil(Mirror(reflecting: editor.view).descendant("paletteDrag")))
        editor.model.drag(.tap, .cancelled, .zero)
        #expect(isNil(Mirror(reflecting: editor.view).descendant("paletteDrag")))
        #expect(editor.profile.controls.isEmpty)
    }
}
