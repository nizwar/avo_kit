import AppKit
import os

private let barsLogger = Logger(subsystem: AvoKitLog.subsystem, category: "FullScreenBars")

/// A full-screen game window's bars kept out of the game (Avo's app windows,
/// Avo Hub's mirror windows): the menu bar and the title bar stay away until
/// the pointer reaches the top of the screen, come down there at once, and go
/// again once the pointer is back in the game, as in other full-screen apps.
///
/// It is done with the presentation options alone, which AppKit's title bar
/// follows (it is a window of its own in full screen, NSToolbarFullScreenWindow):
/// the menu bar hidden takes the title bar with it, the menu bar shown brings
/// both, over the game (the window keeps its size). Two earlier ways failed
/// the user (2026-10-25): AppKit's auto-hiding menu bar, switched on as the
/// pointer reached the top, waits for it to rest there, so the bars came only
/// sometimes; and the title bar's window shown by its alpha with the menu bar
/// hidden stayed empty (AppKit had slid its contents away, as the logs showed:
/// the window at the top, opaque, nothing in it). While the mouse is locked
/// for aiming the pointer stays put, so nothing comes down. Each change is
/// logged (com.avodroid, FullScreenBars).
@MainActor
public final class FullScreenBars {
    /// Over the game: no menu bar (and so no title bar), no Dock.
    public static let hidden: NSApplication.PresentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
    /// Down: the menu bar shown, the title bar with it, over the game.
    public static let shown: NSApplication.PresentationOptions = [.fullScreen, .autoHideDock]
    /// AppKit's own full screen: what another app gets while this one is in
    /// the back, so nothing hidden here lingers over it (Avo #11).
    public static let system: NSApplication.PresentationOptions = [.fullScreen, .autoHideDock, .autoHideMenuBar]
    /// How close to the top the pointer brings the bars, and how far below it
    /// takes them away again (the menu bar and the title bar are about 62 pt).
    static let revealEdge: CGFloat = 2
    static let concealDistance: CGFloat = 90

    private weak var window: NSWindow?
    /// The bars are down (`show`).
    public private(set) var isShown = false
    /// AppKit's full-screen animation runs: the pointer brings nothing down.
    public var inTransition = false
    /// The mouse is locked for aiming: the pointer brings nothing down.
    public var pointerLocked: () -> Bool = { false }
    /// Something under the bar keeps it down while it shows (Avo's Quick
    /// Settings); a haze menu always does.
    public var keepsShown: () -> Bool = { false }
    /// Runs as the bars come down, with the title bar's full-screen layout
    /// (Avo fits its sides).
    public var willShow: () -> Void = {}
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    public init(window: NSWindow) {
        self.window = window
        let center = NotificationCenter.default
        // AppKit saves a full-screen window's presentation options as its app
        // goes to the back and restores them as it comes back; options set by
        // hand miss that, so the bars are handed back and taken again here.
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reclaim() }
            },
        ]
    }

    private var inFullScreen: Bool { window?.styleMask.contains(.fullScreen) == true }

    // MARK: The window's full screen

    /// What `window(_:willUseFullScreenPresentationOptions:)` returns: the
    /// bars start out of the game.
    public var presentationOptions: NSApplication.PresentationOptions { Self.hidden }

    /// `windowDidEnterFullScreen`: the bars go, and the pointer at the top
    /// brings them.
    public func entered() {
        show(false)
        watch(true)
    }

    /// `windowWillExitFullScreen`: the bars are the window's again.
    public func leaving() {
        watch(false)
        isShown = true
    }

    /// `windowDidExitFullScreen`.
    public func left() {
        NSApp.presentationOptions = []
    }

    /// `windowWillClose`.
    public func stop() {
        watch(false)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    /// Another app comes to the front: the bars go back to the system (its
    /// own full screen only auto-hides), so nothing hidden here lingers over
    /// that app.
    public func release() {
        guard inFullScreen else { return }
        NSApp.presentationOptions = Self.system
    }

    /// Active again: the bars as they were over the game.
    public func reclaim() {
        guard inFullScreen, !inTransition else { return }
        NSApp.presentationOptions = isShown ? Self.shown : Self.hidden
    }

    // MARK: Showing

    private func show(_ shown: Bool) {
        guard inFullScreen else { return }
        isShown = shown
        // The title bar has its full-screen layout by now.
        if shown { willShow() }
        let options = shown ? Self.shown : Self.hidden
        // The same options again would set AppKit's bar animation going for nothing.
        if NSApp.presentationOptions != options { NSApp.presentationOptions = options }
        let bar = window?.standardWindowButton(.closeButton)?.window
        barsLogger.info("""
            bars \(shown ? "down" : "up", privacy: .public): options \(NSApp.presentationOptions.rawValue, privacy: .public), \
            title bar \(bar.map { NSStringFromRect($0.frame) } ?? "none", privacy: .public), \
            window \(self.window.map { NSStringFromRect($0.frame) } ?? "none", privacy: .public)
            """)
    }

    // MARK: The pointer

    /// Follows the pointer in full screen: the top edge brings the bars,
    /// moving back down into the game takes them away.
    private func watch(_ on: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard on else { return }
        window?.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
    }

    private func pointerMoved() {
        guard let screen = window?.screen, inFullScreen, !inTransition, !pointerLocked() else { return }
        let at = NSEvent.mouseLocation
        // A drag can go on to another screen: only this one's top counts.
        guard at.x >= screen.frame.minX, at.x < screen.frame.maxX else { return }
        if !isShown, at.y >= screen.frame.maxY - Self.revealEdge {
            show(true)
        } else if isShown, at.y < screen.frame.maxY - Self.concealDistance,
                  // Menus open under the bar: it stays while they show.
                  !keepsShown(), !HazeMenuPresenter.shared.isShown {
            show(false)
        }
    }
}
