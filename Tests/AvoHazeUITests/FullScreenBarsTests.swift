import AppKit
@testable import AvoHazeUI
import Testing

@MainActor
@Suite("Full screen's bars")
struct FullScreenBarsTests {
    /// Hidden, the menu bar takes the title bar with it; down, AppKit's auto-hiding menu bar, made visible, brings
    /// it (options that show the menu bar outright are refused in full screen); another app gets AppKit's own.
    @Test("The bars go with the menu bar and come with AppKit's own, which another app gets too")
    func options() {
        #expect(FullScreenBars.hidden.contains(.hideMenuBar) && FullScreenBars.hidden.contains(.hideDock))
        #expect(FullScreenBars.hidden.contains(.fullScreen) && FullScreenBars.system.contains(.fullScreen))
        #expect(FullScreenBars.system.contains(.autoHideMenuBar) && !FullScreenBars.system.contains(.hideMenuBar))
        #expect(FullScreenBars.system.contains(.autoHideDock))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let bars = FullScreenBars(window: window)
        #expect(bars.presentationOptions == FullScreenBars.hidden)
        // Not in full screen: nothing is touched, the menu bar included.
        let before = NSApplication.shared.presentationOptions
        bars.release()
        bars.reclaim()
        bars.stop()
        #expect(NSApplication.shared.presentationOptions == before)
        #expect(NSMenu.menuBarVisible())
        #expect(!bars.isShown)
    }
}
