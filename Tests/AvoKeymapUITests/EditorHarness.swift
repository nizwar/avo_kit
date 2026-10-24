import AppKit
import AvoHazeUI
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

/// The editor over a 1200 x 540 game picture filling its view, in a window
/// that is never shown, driven as the player drives it: mouse and key
/// events sent to the view, the panel's model called as its buttons call
/// it, and the layout read back from the view (y up in the view: a
/// normalized point (x, y) is at (x · 1200, 540 − y · 540)).
@MainActor
final class Editor {
    final class Saved { var profile: KeymapProfile? }
    let window: NSWindow
    let view: KeymapEditorView
    let saved = Saved()

    init(_ profile: KeymapProfile) {
        _ = NSApplication.shared
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 540), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let box = saved
        view = KeymapEditorView(displayRect: { CGRect(x: 0, y: 0, width: 1200, height: 540) }, profile: profile,
                                onSave: { box.profile = $0; return nil })
        window.contentView = view
    }

    func close() { window.contentView = nil }

    /// The layout as the editor has it now.
    var profile: KeymapProfile { Mirror(reflecting: view).descendant("profile") as! KeymapProfile }
    /// The panel's model, as its buttons call it.
    var model: KeymapEditorModel { Mirror(reflecting: view).descendant("barModel") as! KeymapEditorModel }

    func point(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x * 1200, y: 540 - y * 540) }

    private func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// A drag on the game from `a` to `b` (normalized), in a few steps.
    func drag(from a: (Double, Double), to b: (Double, Double), steps: Int = 4) {
        view.mouseDown(with: event(.leftMouseDown, point(a.0, a.1)))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            view.mouseDragged(with: event(.leftMouseDragged, point(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)))
        }
        view.mouseUp(with: event(.leftMouseUp, point(b.0, b.1)))
    }

    /// ⌥ (and ⇧ with `shift`) + an arrow key.
    func nudge(keyCode: UInt16, shift: Bool = false) {
        let arrow = String(Character(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!))
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.option, .shift] : [.option],
                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: window.windowNumber, context: nil, characters: arrow, charactersIgnoringModifiers: arrow,
                                 isARepeat: false, keyCode: keyCode)!
        view.keyDown(with: e)
    }

    /// A key's event (its Mac key code), with the modifiers held.
    private func keyEvent(_ type: NSEvent.EventType, _ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    /// A key pressed on the editor.
    func press(_ keyCode: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) {
        view.keyDown(with: keyEvent(.keyDown, keyCode, characters, flags))
    }

    /// A shortcut, as macOS offers it to the window's views before the menus.
    @discardableResult
    func shortcut(_ keyCode: UInt16, _ characters: String, flags: NSEvent.ModifierFlags) -> Bool {
        view.performKeyEquivalent(with: keyEvent(.keyDown, keyCode, characters, flags))
    }

    /// A modifier key going down or up; `flags`: the modifiers held after it.
    func modifier(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        view.flagsChanged(with: keyEvent(.flagsChanged, keyCode, "", flags))
    }

    /// A right click on the game at `p` (normalized).
    func rightClick(_ x: Double, _ y: Double) {
        view.rightMouseDown(with: NSEvent.mouseEvent(with: .rightMouseDown, location: point(x, y), modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    }

    /// A click on the game at `p` (normalized).
    func click(_ x: Double, _ y: Double) {
        view.mouseDown(with: event(.leftMouseDown, point(x, y)))
        view.mouseUp(with: event(.leftMouseUp, point(x, y)))
    }

    /// The item of `entries` titled `title`, in their submenus too.
    func item(_ title: String, in entries: [HazeMenuEntry]) -> HazeMenuItem? {
        for entry in entries {
            guard case .item(let item) = entry else { continue }
            if item.title == title { return item }
            if let submenu = item.submenu, let found = self.item(title, in: submenu()) { return found }
        }
        return nil
    }
}

/// Mac key codes the tests press.
enum MacKey {
    static let escape: UInt16 = 53, delete: UInt16 = 51, g: UInt16 = 5, z: UInt16 = 6, s: UInt16 = 1, f: UInt16 = 3
    static let command: UInt16 = 55, shift: UInt16 = 56, option: UInt16 = 58
}

let rightArrow: UInt16 = 0x7C, upArrow: UInt16 = 0x7E

/// A tap with a zone 0.1 wide and 0.2 tall around it.
func tapWithZone(_ id: String = "t", at p: NormalizedPoint = NormalizedPoint(0.5, 0.5)) -> Control {
    Control(id: id, kind: .tap(p), triggers: [.key(.t)],
            clickZone: ClickZone(area: NormalizedRect(p.x - 0.05, p.y - 0.1, p.x + 0.05, p.y + 0.1), shape: .rectangle))
}

func near(_ a: Double?, _ b: Double, within tolerance: Double = 0.005) -> Bool {
    a.map { abs($0 - b) < tolerance } ?? false
}
