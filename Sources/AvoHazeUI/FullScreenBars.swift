// AppKit windows and menus: macOS only.
#if os(macOS)
import AppKit
import os

private let barsLogger = Logger(subsystem: AvoKitLog.subsystem, category: "FullScreenBars")

/// A full-screen game window's bars kept out of the game (Avo's app windows,
/// Avo Hub's mirror windows): the menu bar and the title bar stay away until
/// the pointer reaches the top of the screen, come down there at once, and go
/// again once the pointer is back in the game, as in other full-screen apps.
///
/// AppKit's title bar (a window of its own in full screen,
/// NSToolbarFullScreenWindow) follows the menu bar: hidden, it takes the
/// title bar with it; shown, it brings both over the game (the window keeps
/// its size). What macOS takes in full screen, from probes on macOS 27
/// (2026-10-25):
/// - Options that show the menu bar outright are refused: they read back as
///   the hidden ones, so the bars never came down (Avo Hub b17).
/// - `NSMenu.setMenuBarVisible(false)` takes both away, and keeps them away:
///   auto-hiding options set after it are held back until
///   `setMenuBarVisible(true)`, which then brings the menu bar and the title
///   bar down at once (in about 0.3 s, the slide).
/// Two earlier ways failed the user too: AppKit's auto-hiding menu bar alone,
/// switched on as the pointer reached the top, waits for it to rest there,
/// so the bars came only sometimes; and the title bar's window shown by its
/// alpha with the menu bar hidden stayed empty (AppKit slides its contents
/// away). While the mouse is locked for aiming the pointer stays put, so
/// nothing comes down. Each change is logged (com.avodroid, FullScreenBars).
@MainActor
public final class FullScreenBars {
    /// Over the game: no menu bar (and so no title bar), no Dock.
    public static let hidden: NSApplication.PresentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
    /// AppKit's own full screen, its menu bar auto-hiding: made visible, it
    /// brings the bars down; and what another app gets while this one is in
    /// the back, so nothing hidden here lingers over it (Avo #11).
    public static let system: NSApplication.PresentationOptions = [.fullScreen, .autoHideDock, .autoHideMenuBar]
    /// How close to the top the pointer brings the bars, and how far below it
    /// takes them away again (the menu bar and the title bar are about 62 pt).
    static let revealEdge: CGFloat = 2
    static let concealDistance: CGFloat = 90

    private weak var window: NSWindow?
    /// The bars are down (`show`).
    public private(set) var isShown = false
    /// The menu bar is hidden from here (`setMenuBarVisible(false)`), which
    /// holds for the whole app until it is made visible again.
    private var hidingMenuBar = false
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
        // The same as the window's space goes to the back (another space, with
        // the app's other windows, comes to the front): the hidden menu bar
        // holds for the whole app.
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reclaim() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    if window.isOnActiveSpace { self.reclaim() } else { self.release() }
                }
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

    /// `windowDidExitFullScreen`: the menu bar as it is everywhere else.
    public func left() {
        giveBackMenuBar()
        NSApp.presentationOptions = []
    }

    /// `windowWillClose`: a window closed in full screen never gets `left`.
    public func stop() {
        watch(false)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        if hidingMenuBar {
            giveBackMenuBar()
            NSApp.presentationOptions = []
        }
    }

    /// Another app, or another space, comes to the front: the bars go back to
    /// the system (its own full screen only auto-hides), so nothing hidden
    /// here lingers there.
    public func release() {
        guard inFullScreen else { return }
        NSApp.presentationOptions = Self.system
        giveBackMenuBar()
    }

    /// Active again, on this window's space: the bars as they were over the
    /// game, down only while the pointer is still up there.
    public func reclaim() {
        guard inFullScreen, !inTransition, window?.isOnActiveSpace != false else { return }
        show(isShown && pointerNearTop)
    }

    // MARK: Showing

    private func show(_ shown: Bool) {
        guard inFullScreen else { return }
        isShown = shown
        let started = ContinuousClock.now
        if shown {
            // The title bar has its full-screen layout by now.
            willShow()
            // Held back while the menu bar is hidden; made visible, it comes down with the title bar.
            if NSApp.presentationOptions != Self.system { NSApp.presentationOptions = Self.system }
            giveBackMenuBar()
        } else {
            NSMenu.setMenuBarVisible(false)
            hidingMenuBar = true
            // The same options again would set AppKit's bar animation going for nothing.
            if NSApp.presentationOptions != Self.hidden { NSApp.presentationOptions = Self.hidden }
        }
        // How long AppKit held the main thread for it (the game's frames wait meanwhile).
        let elapsed = (ContinuousClock.now - started).components
        let took = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        barsLogger.info("""
            bars \(shown ? "down" : "up", privacy: .public) in \(took, privacy: .public) ms: \
            options \(NSApp.presentationOptions.rawValue, privacy: .public), title bar at \(self.titlebarFrame.map { NSStringFromRect($0) } ?? "none", privacy: .public), \
            window \(self.window.map { NSStringFromRect($0.frame) } ?? "none", privacy: .public)
            """)
    }

    private func giveBackMenuBar() {
        NSMenu.setMenuBarVisible(true)
        hidingMenuBar = false
    }

    /// The title bar's contents on the screen: above the screen's top while
    /// AppKit has slid them away, below it while the bar is down.
    private var titlebarFrame: NSRect? {
        guard let view = window?.standardWindowButton(.closeButton)?.superview, let barWindow = view.window else { return nil }
        return barWindow.convertToScreen(view.convert(view.bounds, to: nil))
    }

    /// The bar is on the screen: AppKit's auto-hiding can take it away by
    /// itself while it is meant to be down.
    private var barOnScreen: Bool {
        guard let frame = titlebarFrame, let screen = window?.screen else { return false }
        return frame.minY < screen.frame.maxY - 1
    }

    private var pointerNearTop: Bool {
        guard let screen = window?.screen else { return false }
        let at = NSEvent.mouseLocation
        return at.x >= screen.frame.minX && at.x < screen.frame.maxX && at.y >= screen.frame.maxY - Self.concealDistance
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
        if at.y >= screen.frame.maxY - Self.revealEdge, !isShown || !barOnScreen {
            show(true)
        } else if isShown, at.y < screen.frame.maxY - Self.concealDistance,
                  // Menus open under the bar: it stays while they show.
                  !keepsShown(), !HazeMenuPresenter.shared.isShown {
            show(false)
        }
    }
}
#endif
