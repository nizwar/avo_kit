import AppKit
import AvoHazeUI
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

// The editor's keys: the next key is the selected control's, but a
// shortcut's modifiers, Esc, Delete and ⌘Z are the editor's own.

private func tap(_ id: String = "t", _ x: Double = 0.5, _ y: Double = 0.5, key: KeyName = .t) -> Control {
    Control(id: id, kind: .tap(NormalizedPoint(x, y)), triggers: [.key(key)])
}

@MainActor
@Suite("The key mapping editor's keys")
struct KeymapEditorKeysTests {
    @Test("A shortcut's modifier never becomes the selected control's key")
    func shortcutsBindNothing() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.model.select("t")
        // ⌘G: ⌘ down, the shortcut, ⌘ up.
        editor.modifier(MacKey.command, flags: [.command])
        editor.shortcut(MacKey.g, "g", flags: [.command])
        editor.modifier(MacKey.command, flags: [])
        #expect(editor.profile.controls[0].triggers == [.key(.t)])
        // ⇧⌘S held as two modifiers, let go without the letter.
        editor.modifier(MacKey.command, flags: [.command])
        editor.modifier(MacKey.shift, flags: [.command, .shift])
        editor.modifier(MacKey.shift, flags: [.command])
        editor.modifier(MacKey.command, flags: [])
        #expect(editor.profile.controls[0].triggers == [.key(.t)])
        // A modifier pressed and let go on its own still is a key.
        editor.modifier(MacKey.shift, flags: [.shift])
        editor.modifier(MacKey.shift, flags: [])
        #expect(editor.profile.controls[0].triggers == [.key(.shift)])
    }

    @Test("Esc is a key like any other: a new tap takes it, and so does the selected control")
    func escapeIsAKey() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.click(0.2, 0.2)
        #expect(Mirror(reflecting: editor.view).descendant("pendingTap") as? NormalizedPoint != nil)
        editor.press(MacKey.escape)
        #expect(Mirror(reflecting: editor.view).descendant("pendingTap") as? NormalizedPoint == nil)
        #expect(editor.profile.controls.count == 2, "the tap is placed, not thrown away")
        #expect(editor.profile.controls.last?.triggers == [.key(.escape)])
        editor.model.select("t")
        editor.press(MacKey.escape)
        #expect(editor.profile.controls[0].triggers == [.key(.escape)])
    }

    @Test("Delete takes back a waiting tap")
    func deleteCancelsAWaitingTap() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.click(0.2, 0.2)
        editor.press(MacKey.delete)
        #expect(Mirror(reflecting: editor.view).descendant("pendingTap") as? NormalizedPoint == nil)
        #expect(editor.profile.controls.map(\.id) == ["t"])
    }

    @Test("Delete removes the selected control, and ⌘Z brings it back")
    func deleteAndUndo() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap(), tap("u", 0.2, 0.2, key: .u)]))
        defer { editor.close() }
        editor.model.select("t")
        editor.press(MacKey.delete)
        #expect(editor.profile.controls.map(\.id) == ["u"])
        #expect(editor.shortcut(MacKey.z, "z", flags: [.command]))
        #expect(editor.profile.controls.map(\.id) == ["t", "u"])
        #expect(editor.model.selection?.control.id == "t", "selected again, as it was")
        // Nothing left to undo.
        editor.view.undo()
        #expect(editor.model.status == String(localized: "Nothing to undo.", bundle: .avoSharedKit))
    }

    @Test("A drag is one change for ⌘Z")
    func aDragIsOneUndoStep() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.drag(from: (0.5, 0.5), to: (0.7, 0.3), steps: 6)
        #expect(editor.profile.controls[0].kind == .tap(NormalizedPoint(0.7, 0.3)))
        editor.view.undo()
        #expect(editor.profile.controls[0].kind == .tap(NormalizedPoint(0.5, 0.5)))
    }

    @Test("Removing the eye, with what only it made sense with, is one ⌘Z")
    func removingTheEyeIsOneUndoStep() {
        let eye = Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                                adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: nil))
        let free = Control(id: "free", kind: .hotkey, triggers: [.key(.g)], actions: [.freeMouse])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [eye, free], fps: FPSSettings(aimControl: "eye")))
        defer { editor.close() }
        editor.model.select("eye")
        editor.model.remove()
        #expect(editor.profile.controls.isEmpty)
        #expect(editor.profile.fps == nil)
        editor.view.undo()
        #expect(editor.profile.controls.map(\.id) == ["eye", "free"])
        #expect(editor.profile.fps?.aimControl == "eye")
    }

    @Test("Undoing a control's adding lets go of it")
    func undoingAnAddLetsGoOfIt() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: []))
        defer { editor.close() }
        editor.model.add(.tap)
        #expect(editor.model.selection != nil)
        editor.view.undo()
        #expect(editor.profile.controls.isEmpty)
        #expect(editor.model.selection == nil)
    }

    @Test("Delete is a control's key from its menu")
    func deleteFromTheMenu() throws {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap()]))
        defer { editor.close() }
        editor.model.select("t")
        let delete = try #require(editor.item(String(localized: "Delete Key", bundle: .avoSharedKit), in: editor.model.mouseButtons()))
        delete.action()
        #expect(editor.profile.controls[0].triggers == [.key(.delete)])
    }
}
