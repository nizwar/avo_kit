import AppKit
@testable import AvoHazeUI
import Testing

@MainActor
@Suite("Full screen's bars")
struct FullScreenBarsTests {
    /// The title bar's window counts as shown only while most of it is on its screen: AppKit moves it up out of
    /// the screen where its own reveal brings it, and then that reveal is used.
    @Test("A title bar is on the screen while most of it is")
    func titleBarOnScreen() throws {
        let screen = try #require(NSScreen.screens.first)
        let top = screen.frame.maxY
        let bar = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        bar.setFrame(NSRect(x: screen.frame.minX, y: top - 62, width: screen.frame.width, height: 62), display: false)
        #expect(FullScreenBars.isOnScreen(bar, screen))
        bar.setFrame(NSRect(x: screen.frame.minX, y: top - 20, width: screen.frame.width, height: 62), display: false)
        #expect(!FullScreenBars.isOnScreen(bar, screen), "mostly above the screen")
        bar.setFrame(NSRect(x: screen.frame.minX, y: top, width: screen.frame.width, height: 62), display: false)
        #expect(!FullScreenBars.isOnScreen(bar, screen))
        #expect(!FullScreenBars.isOnScreen(bar, nil))
    }

    @Test("The bars start out of the game, and another app gets AppKit's own")
    func options() {
        #expect(FullScreenBars.hidden.contains(.hideMenuBar) && FullScreenBars.hidden.contains(.hideDock))
        #expect(FullScreenBars.system.contains(.autoHideMenuBar) && !FullScreenBars.system.contains(.hideMenuBar))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let bars = FullScreenBars(window: window)
        defer { bars.stop() }
        #expect(bars.presentationOptions == FullScreenBars.hidden)
        // Not in full screen: nothing is touched.
        let before = NSApplication.shared.presentationOptions
        bars.release()
        bars.reclaim()
        #expect(NSApplication.shared.presentationOptions == before)
        #expect(!bars.isShown)
    }
}
