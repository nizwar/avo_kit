import AppKit
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
private final class Editor {
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
}

private let rightArrow: UInt16 = 0x7C, upArrow: UInt16 = 0x7E

/// A tap with a zone 0.1 wide and 0.2 tall around it.
private func tapWithZone(_ id: String = "t", at p: NormalizedPoint = NormalizedPoint(0.5, 0.5)) -> Control {
    Control(id: id, kind: .tap(p), triggers: [.key(.t)],
            clickZone: ClickZone(area: NormalizedRect(p.x - 0.05, p.y - 0.1, p.x + 0.05, p.y + 0.1), shape: .rectangle))
}

private func near(_ a: Double?, _ b: Double, within tolerance: Double = 0.005) -> Bool {
    a.map { abs($0 - b) < tolerance } ?? false
}

@MainActor
@Suite("The key mapping editor's click zones, scroll bars and list")
struct KeymapEditorTests {
    // MARK: Click zones

    @Test("A click zone's edge and inside are dragged on the game")
    func zoneDrags() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tapWithZone()]))
        defer { editor.close() }
        editor.model.select("t")
        // The right edge (x 0.55) dragged right to 0.6.
        editor.drag(from: (0.55, 0.5), to: (0.6, 0.5))
        let widened = editor.profile.controls[0].clickZone?.area
        #expect(near(widened?.maxX, 0.6) && near(widened?.minX, 0.45), "zone is \(String(describing: widened))")
        // Its inside, away from the button, dragged down: the button stays.
        editor.drag(from: (0.46, 0.43), to: (0.46, 0.53))
        let moved = editor.profile.controls[0].clickZone?.area
        #expect(near(moved?.minY, 0.5) && near(moved?.maxY, 0.7), "zone is \(String(describing: moved))")
        #expect(editor.profile.controls[0].kind == .tap(NormalizedPoint(0.5, 0.5)))
    }

    @Test("A zone follows its button, and comes back around it after the screen's edge held it")
    func zoneFollowsItsButton() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tapWithZone()]))
        defer { editor.close() }
        editor.drag(from: (0.5, 0.5), to: (0.3, 0.7))
        var zone = editor.profile.controls[0].clickZone?.area
        #expect(near(zone?.center.x, 0.3, within: 0.002) && near(zone?.center.y, 0.7, within: 0.002), "\(String(describing: zone))")
        // To the right edge: the zone stays on the screen, against it.
        editor.model.deselect()
        editor.drag(from: (0.3, 0.7), to: (1.0, 0.5))
        zone = editor.profile.controls[0].clickZone?.area
        #expect(near(zone?.maxX, 1) && near(zone?.width, 0.1), "\(String(describing: zone))")
        // Back again (deselected, so the drag takes the button, not the zone's edge).
        editor.model.deselect()
        editor.drag(from: (1.0, 0.5), to: (0.5, 0.5))
        let control = editor.profile.controls[0]
        #expect(control.kind == .tap(NormalizedPoint(0.5, 0.5)))
        #expect(near(control.clickZone?.area.center.x, 0.5) && near(control.clickZone?.area.center.y, 0.5),
                "the zone's middle is at \(String(describing: control.clickZone?.area.center)), the button at 0.5")
        #expect(KeymapProfile(package: "x", name: "x", controls: editor.profile.controls).validate().isEmpty)
        // ⌥ + an arrow key moves the button (still selected from the drag) with its zone.
        editor.nudge(keyCode: rightArrow)
        #expect(near(editor.profile.controls[0].buttonPoint?.x, 0.51, within: 1e-9))
        #expect(near(editor.profile.controls[0].clickZone?.area.center.x, 0.51, within: 1e-9))
    }

    @Test("The toggle takes a zone away and makes a new one around the button")
    func zoneToggle() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tapWithZone(at: NormalizedPoint(0.3, 0.7))]))
        defer { editor.close() }
        editor.model.select("t")
        editor.model.setClickZone(false)
        #expect(editor.profile.controls[0].clickZone == nil)
        editor.model.setClickZone(true)
        let fresh = editor.profile.controls[0].clickZone?.area
        #expect(near(fresh?.center.x, 0.3, within: 0.002) && near(fresh?.center.y, 0.7, within: 0.002))
        #expect(KeymapProfile(package: "x", name: "x", controls: editor.profile.controls).validate().isEmpty)
    }

    @Test("A hotkey's zone is moved by ⌥ + arrow keys, and picked and dragged by its inside")
    func hotkeyZone() throws {
        let hotkey = Control(id: "h", kind: .hotkey, triggers: [.key(.h)], actions: [.switchMode("b")])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [hotkey],
                                          modes: [KeymapMode(id: "a", name: "A"), KeymapMode(id: "b", name: "B")]))
        defer { editor.close() }
        editor.model.select("h")
        editor.model.setClickZone(true)
        let made = try #require(editor.profile.controls[0].clickZone?.area)
        editor.nudge(keyCode: rightArrow)
        let moved = try #require(editor.profile.controls[0].clickZone?.area)
        #expect(near(moved.minX, made.minX + 0.01, within: 1e-9), "⌥→ left the zone at \(moved)")
        // Deselected, a click inside the zone picks the hotkey again, and its drag moves the zone.
        editor.model.deselect()
        let start = moved.center
        editor.drag(from: (start.x, start.y), to: (start.x - 0.2, start.y + 0.1))
        #expect(editor.model.selection?.control.id == "h")
        let dragged = editor.profile.controls[0].clickZone?.area
        #expect(near(dragged?.center.x, start.x - 0.2) && near(dragged?.center.y, start.y + 0.1), "\(String(describing: dragged))")
        #expect(KeymapProfile(package: "x", name: "x", controls: editor.profile.controls,
                              modes: [KeymapMode(id: "a", name: "A"), KeymapMode(id: "b", name: "B")]).validate().isEmpty)
    }

    @Test("A macro's zone is moved by ⌥ + arrow keys (the macro stays where its first tap is)")
    func macroZone() {
        let p = NormalizedPoint(0.4, 0.4)
        let macro = Control(id: "m", kind: .macro([.tap(p), .wait(milliseconds: 50), .tap(p)]), triggers: [.key(.m)],
                            clickZone: ClickZone(area: NormalizedRect(0.35, 0.3, 0.45, 0.5)))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [macro]))
        defer { editor.close() }
        editor.model.select("m")
        editor.nudge(keyCode: upArrow)
        #expect(near(editor.profile.controls[0].clickZone?.area.minY, 0.29, within: 1e-9))
    }

    @Test("⌥⇧ + arrow keys size an anchor's reach with a zone, and the zone once it is taken hold of")
    func zoneOrReachSized() {
        let anchor = Control(id: "a", kind: .anchor(NormalizedPoint(0.5, 0.5), radius: 0.18), triggers: [.key(.t)],
                             clickZone: ClickZone(area: NormalizedRect(0.45, 0.4, 0.55, 0.6)))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [anchor]))
        defer { editor.close() }
        editor.model.select("a")
        editor.nudge(keyCode: upArrow, shift: true)
        guard case .anchor(_, let radius?) = editor.profile.controls[0].kind else { Issue.record("not an anchor"); return }
        #expect(radius > 0.19, "the reach stayed \(radius)")
        #expect(editor.profile.controls[0].clickZone?.area == NormalizedRect(0.45, 0.4, 0.55, 0.6))
        // Its zone's edge dragged: now the keys size the zone, and the reach stays.
        editor.drag(from: (0.55, 0.5), to: (0.56, 0.5), steps: 1)
        let before = editor.profile.controls[0].clickZone?.area
        editor.nudge(keyCode: upArrow, shift: true)
        let after = editor.profile.controls[0].clickZone?.area
        #expect(near(after?.height, (before?.height ?? 0) + 0.02, within: 1e-9), "\(String(describing: before)) → \(String(describing: after))")
        guard case .anchor(_, let kept?) = editor.profile.controls[0].kind else { Issue.record("not an anchor"); return }
        #expect(kept == radius)
        // And ⌥ + an arrow key moves the zone alone.
        editor.nudge(keyCode: rightArrow)
        #expect(editor.profile.controls[0].kind == .anchor(NormalizedPoint(0.5, 0.5), radius: radius))
        #expect(near(editor.profile.controls[0].clickZone?.area.minX, (after?.minX ?? 0) + 0.01, within: 1e-9))
        // The button taken hold of again: the keys move it, with its zone.
        editor.drag(from: (0.5, 0.5), to: (0.5, 0.5), steps: 1)
        editor.nudge(keyCode: rightArrow)
        #expect(near(editor.profile.controls[0].buttonPoint?.x, 0.51, within: 1e-9))
        #expect(near(editor.profile.controls[0].clickZone?.area.minX, (after?.minX ?? 0) + 0.02, within: 1e-9))
    }

    @Test("A button's zone is sized by ⌥⇧ + arrow keys: the button has no size of its own")
    func buttonZoneSized() {
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tapWithZone()]))
        defer { editor.close() }
        editor.model.select("t")
        editor.nudge(keyCode: rightArrow, shift: true)
        #expect(near(editor.profile.controls[0].clickZone?.area.width, 0.12, within: 1e-9))
    }

    @Test("A control that works only with the mouse locked gets no zone: clicks press controls only while it is free")
    func lockedControlGetsNoZone() {
        let fire = Control(id: "fire", kind: .tap(NormalizedPoint(0.8, 0.7)), triggers: [.mouse(.left)], layer: .locked)
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [fire]))
        defer { editor.close() }
        editor.model.select("fire")
        editor.model.setClickZone(true)
        #expect(editor.profile.controls[0].clickZone == nil)
        #expect(editor.model.problem)
        // One it has already (from a file) can still be turned off.
        var zoned = fire
        zoned.clickZone = ClickZone(area: NormalizedRect(0.75, 0.6, 0.85, 0.8))
        let other = Editor(KeymapProfile(package: "x", name: "x", controls: [zoned]))
        defer { other.close() }
        other.model.select("fire")
        other.model.setClickZone(false)
        #expect(other.profile.controls[0].clickZone == nil)
    }

    // MARK: Scroll bars

    @Test("Turned across or up and down, a scroll bar keeps its length on the screen and stays on it")
    func scrollBarTurns() {
        let aspect = 2400.0 / 1080
        var bar = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.5, 0.8), to: NormalizedPoint(0.5, 0.2), rest: 0.5, step: 0.1))
        bar.setScrollBar(vertical: false, aspect: aspect)
        guard case let .scrollBar(from, to, _, _) = bar.kind else { Issue.record("not a bar"); return }
        let tall = 0.6 * 1080
        #expect(abs(abs(to.x - from.x) * 2400 - tall) < 1, "\(Int(tall)) px tall became \(Int(abs(to.x - from.x) * 2400)) px wide")
        #expect(abs((from.x + to.x) / 2 - 0.5) < 1e-9 && from.y == 0.5 && to.y == 0.5)
        #expect(to.x > from.x, "wheel up still drags it the same way (up: right)")
        // Near the right edge: moved onto the screen, as long as it was.
        var edge = Control(id: "e", kind: .scrollBar(from: NormalizedPoint(0.95, 0.8), to: NormalizedPoint(0.95, 0.2), rest: 0.5, step: 0.1))
        edge.setScrollBar(vertical: false, aspect: aspect)
        guard case let .scrollBar(f2, t2, _, _) = edge.kind else { Issue.record("not a bar"); return }
        #expect(abs(abs(t2.x - f2.x) * 2400 - tall) < 1, "\(Int(abs(t2.x - f2.x) * 2400)) px wide at the edge, from \(f2.x) to \(t2.x)")
        #expect(max(f2.x, t2.x) <= 1)
        // And back: as tall as it was.
        edge.setScrollBar(vertical: true, aspect: aspect)
        guard case let .scrollBar(f3, t3, _, _) = edge.kind else { Issue.record("not a bar"); return }
        #expect(abs(abs(t3.y - f3.y) - 0.6) < 1e-9 && t3.y < f3.y)
        // A short one turned upright is no shorter than the editor makes one.
        var short = Control(id: "h", kind: .scrollBar(from: NormalizedPoint(0.3, 0.5), to: NormalizedPoint(0.31, 0.5), rest: 0.5, step: 0.1))
        short.setScrollBar(vertical: true, aspect: aspect)
        guard case let .scrollBar(f4, t4, _, _) = short.kind else { Issue.record("not a bar"); return }
        #expect(abs(t4.y - f4.y) >= Control.minimumScrollTrack - 1e-12)
    }

    @Test("A track across dragged as short as the editor lets it saves (a 20:9 picture)")
    func shortestTrackSaves() {
        let bar = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.3, 0.5), to: NormalizedPoint(0.6, 0.5), rest: 0.5, step: 0.1))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [bar]))
        defer { editor.close() }
        editor.model.select("s")
        editor.drag(from: (0.6, 0.5), to: (0.3, 0.5))
        guard case let .scrollBar(from, to, _, _) = editor.profile.controls[0].kind else { Issue.record("not a bar"); return }
        #expect(to.x > from.x, "the end kept its side")
        editor.model.done()
        #expect(editor.saved.profile != nil, "Done refused: \(editor.model.status)")
    }

    @Test("A scroll bar over the eye's area says it works only while the mouse is free")
    func scrollBarOverTheEye() {
        let eye = Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                                adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: nil))
        let over = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1))
        let beside = Control(id: "b", kind: .scrollBar(from: NormalizedPoint(0.2, 0.8), to: NormalizedPoint(0.2, 0.2), rest: 0.5, step: 0.1))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [eye, over, beside], fps: FPSSettings(aimControl: "eye")))
        defer { editor.close() }
        editor.model.select("s")
        #expect(editor.model.barsOverTheEye == ["s"])
        #expect(editor.profile.scrollBarsOverTheAimArea == ["s"])
    }

    @Test("The panel's Direction turns a scroll bar on the editor's own picture")
    func scrollBarTurnedFromThePanel() {
        let bar = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.5, 0.8), to: NormalizedPoint(0.5, 0.2), rest: 0.5, step: 0.1))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [bar]))
        defer { editor.close() }
        editor.model.select("s")
        #expect(abs(editor.model.displayAspect() - 1200.0 / 540) < 1e-9)
        let aspect = editor.model.displayAspect()
        editor.model.update { $0.setScrollBar(vertical: false, aspect: aspect) }
        guard case let .scrollBar(from, to, _, _) = editor.profile.controls[0].kind else { Issue.record("not a bar"); return }
        #expect(abs(abs(to.x - from.x) * 1200 - 0.6 * 540) < 1)
    }

    @Test("Flipping a scroll bar's direction keeps its rest point on the same spot, and turning it keeps wheel up's way")
    func scrollBarFlips() throws {
        for (from, to) in [(NormalizedPoint(0.9, 0.8), NormalizedPoint(0.9, 0.2)), (NormalizedPoint(0.2, 0.5), NormalizedPoint(0.7, 0.5))] {
            var bar = Control(id: "s", kind: .scrollBar(from: from, to: to, rest: 0.3, step: 0.1))
            let spot = try #require(bar.scrollPoint(at: 0.3))
            let forward = bar.scrollsForward
            bar.setScrollBar(forward: !forward)
            guard case let .scrollBar(_, _, rest, _) = bar.kind else { Issue.record("not a bar"); return }
            let after = try #require(bar.scrollPoint(at: rest))
            #expect(abs(after.x - spot.x) < 1e-9 && abs(after.y - spot.y) < 1e-9)
            #expect(bar.scrollsForward == !forward)
            var turned = Control(id: "s", kind: .scrollBar(from: from, to: to, rest: 0.3, step: 0.1))
            let vertical = turned.isVerticalScrollBar
            turned.setScrollBar(vertical: !vertical)
            #expect(turned.isVerticalScrollBar == !vertical)
            #expect(turned.scrollsForward == forward)
        }
    }

    @Test("A scroll bar's reset key shared with another control says so")
    func sharedResetKey() {
        let bar = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1))
        let tap = Control(id: "t", kind: .tap(NormalizedPoint(0.2, 0.2)), triggers: [.key(.z)])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [bar, tap]))
        defer { editor.close() }
        editor.model.select("s")
        editor.model.setDPadSlot(4)
        editor.view.assign(.key(.z))
        #expect(editor.profile.controls[0].reset == .key(.z))
        let tapName = String(localized: "Tap", bundle: .avoSharedKit)
        #expect(editor.model.status.contains("“\(tapName)”"), "\(editor.model.status)")
    }

    // MARK: The panel

    @Test("The Controls list waits for a key only where one is needed")
    func listedKeys() {
        let area = Control(id: "c", kind: .clickArea(NormalizedRect(0.8, 0, 0.9, 0.1), passThrough: true), actions: [.lockMouse])
        let bar = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1))
        let hotkey = Control(id: "h", kind: .hotkey, actions: [.freeMouse])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [area, bar, hotkey]))
        defer { editor.close() }
        // (Selecting one fills the list.)
        editor.model.select("c")
        let rows = Dictionary(uniqueKeysWithValues: editor.model.listed.map { ($0.id, $0) })
        #expect(rows["c"]?.keys == nil && rows["c"]?.needsKey == false, "a click area is clicked")
        #expect(rows["s"]?.keys != nil, "a scroll bar's wheel")
        #expect(rows["h"]?.keys == nil && rows["h"]?.needsKey == true, "a hotkey still waits for its key")
    }

    // MARK: The eye

    @Test("Removing the eye takes away what only locked or freed the mouse, and the layout still saves")
    func removingTheEye() {
        let eye = Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                                adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: nil))
        let bag = Control(id: "bag", kind: .tap(NormalizedPoint(0.05, 0.05)), triggers: [.key(.tab)], actions: [.freeMouse, .switchMode("b")])
        let free = Control(id: "free", kind: .hotkey, triggers: [.key(.g)], actions: [.freeMouse])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [eye, bag, free], fps: FPSSettings(aimControl: "eye"),
                                          modes: [KeymapMode(id: "a", name: "A"), KeymapMode(id: "b", name: "B")]))
        defer { editor.close() }
        editor.model.select("eye")
        editor.model.remove()
        #expect(editor.profile.controls.map(\.id) == ["bag"])
        #expect(editor.profile.controls[0].actions == [.switchMode("b")])
        #expect(editor.profile.validate().isEmpty, "\(editor.profile.validate())")
        editor.model.done()
        #expect(editor.saved.profile != nil, "Done refused: \(editor.model.status)")
    }

    @Test("The wheel cannot be the eye's key")
    func theEyesKeyIsNotTheWheel() {
        let eye = Control(id: "eye", kind: .aim(area: NormalizedRect(0.5, 0.1, 1, 0.7), sensitivity: AxisPair(x: 1, y: 1),
                                                adsSensitivity: AxisPair(x: 1, y: 1), exponent: 1, deadzone: 0, invertY: false, stick: nil))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [eye], fps: FPSSettings(aimControl: "eye")))
        defer { editor.close() }
        editor.model.select("eye")
        editor.view.assign(.scrollUp)
        #expect(editor.profile.fps?.cursorToggle == FPSSettings.defaultCursorToggle)
        #expect(editor.model.problem)
    }

    @Test("Every kind has a category, and the panel groups them")
    func categories() {
        #expect(KeymapCategory.general.items == [.tap, .repeatTap, .anchor, .joystick, .swipe, .scrollBar, .clickArea, .hotkey])
        #expect(KeymapCategory.fps.items == [.eye, .ads])
        #expect(KeymapCategory.moba.items == [.moveByMouse, .smartCast])
        #expect(Set(KeymapCategory.allCases.flatMap(\.items)) == Set(KeymapPaletteItem.allCases))
        let bar = Control(id: "s", kind: .scrollBar(from: NormalizedPoint(0.9, 0.8), to: NormalizedPoint(0.9, 0.2), rest: 0.5, step: 0.1))
        #expect(KeymapPaletteItem.item(for: bar) == .scrollBar)
        #expect(KeymapPaletteItem.item(for: Control(id: "c", kind: .clickArea(.screen, passThrough: true))) == .clickArea)
        #expect(KeymapPaletteItem.item(for: Control(id: "h", kind: .hotkey)) == .hotkey)
    }
}
