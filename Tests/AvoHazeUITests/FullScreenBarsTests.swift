import AppKit
@testable import AvoHazeUI
import Testing

@MainActor
@Suite("Full screen's bars")
struct FullScreenBarsTests {
    /// Hidden, the menu bar takes the title bar with it; down, the menu bar shows and brings it, at once
    /// (no auto-hiding, which waits for the pointer to rest at the top); another app gets AppKit's own.
    @Test("The bars go with the menu bar and come with it, and another app gets AppKit's own")
    func options() {
        #expect(FullScreenBars.hidden.contains(.hideMenuBar) && FullScreenBars.hidden.contains(.hideDock))
        #expect(!FullScreenBars.shown.contains(.hideMenuBar) && !FullScreenBars.shown.contains(.autoHideMenuBar))
        #expect(FullScreenBars.shown.contains(.fullScreen))
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
