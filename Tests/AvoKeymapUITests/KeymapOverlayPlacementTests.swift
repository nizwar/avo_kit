import AppKit
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

// Where the editor's panel stands beside the game's window: on a display
// with room for it (the one beside the window's too), lined up with the
// game's screen, never a sliver; inside, clear of a phone screen's corners.

@MainActor
@Suite("The key mapping panel beside the window")
struct KeymapOverlayPlacementTests {
    private let width: CGFloat = 348

    @Test("Beside the window on its display, its top at the game's screen")
    func besideTheWindow() throws {
        let display = NSRect(x: 0, y: 0, width: 1920, height: 1050)
        let window = NSRect(x: 200, y: 200, width: 800, height: 600)
        // The Phone app bar style: the screen sits 40 points under the window's top.
        let screen = NSRect(x: 210, y: 210, width: 780, height: 550)
        let frame = try #require(KeymapOverlay.sideFrame(beside: window, content: screen, right: true, screens: [display], width: width,
                                                         gap: 8, minimumHeight: 560))
        #expect(frame.minX == 1008 && frame.maxY == screen.maxY && frame.height == 560)
        // On the left, where there is room (not beside a window 200 points from the display's edge).
        #expect(KeymapOverlay.sideFrame(beside: window, content: screen, right: false, screens: [display], width: width, gap: 8,
                                        minimumHeight: 560) == nil)
        let moved = window.offsetBy(dx: 400, dy: 0)
        let left = try #require(KeymapOverlay.sideFrame(beside: moved, content: screen.offsetBy(dx: 400, dy: 0), right: false, screens: [display],
                                                        width: width, gap: 8, minimumHeight: 560))
        #expect(left.maxX == 592)
    }

    @Test("On the display beside the window's when its own has no room")
    func onTheNextDisplay() throws {
        let own = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let next = NSRect(x: 1440, y: 0, width: 1920, height: 1050)
        let window = NSRect(x: 600, y: 100, width: 840, height: 700)
        #expect(KeymapOverlay.sideFrame(beside: window, content: nil, right: true, screens: [own], width: width, gap: 8, minimumHeight: 560) == nil)
        let frame = try #require(KeymapOverlay.sideFrame(beside: window, content: nil, right: true, screens: [own, next], width: width,
                                                         gap: 8, minimumHeight: 560))
        #expect(next.contains(frame))
    }

    @Test("Never a sliver beside a window low on the display")
    func neverASliver() {
        let display = NSRect(x: 0, y: 0, width: 1920, height: 1050)
        let low = NSRect(x: 200, y: 0, width: 800, height: 150)
        #expect(KeymapOverlay.sideFrame(beside: low, content: nil, right: true, screens: [display], width: width, gap: 8, minimumHeight: 560) == nil)
    }

    @Test("Inside a screen with round corners, the panel stands clear of them")
    func clearOfRoundCorners() throws {
        let editor = KeymapEditorView(displayRect: { CGRect(x: 0, y: 0, width: 800, height: 400) },
                                      profile: KeymapProfile(package: "x", name: "x", controls: []), onSave: { _ in nil })
        let screen = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        screen.wantsLayer = true
        screen.layer?.cornerRadius = 30
        screen.layer?.masksToBounds = true
        editor.frame = screen.bounds
        screen.addSubview(editor)
        editor.layout()
        let inside = try #require(Mirror(reflecting: editor).descendant("panelInside") as? [NSLayoutConstraint])
        #expect(inside[0].constant == 30 && inside[1].constant == -30)
        screen.layer?.masksToBounds = false
        editor.layout()
        #expect(inside[0].constant == 0)
    }
}
