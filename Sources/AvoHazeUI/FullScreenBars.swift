import AppKit
import os

private let barsLogger = Logger(subsystem: AvoKitLog.subsystem, category: "FullScreenBars")

/// A full-screen game window's bars kept out of the game (Avo's app windows,
/// Avo Hub's mirror windows): the title bar stays away until the pointer
/// reaches the top of the screen, comes down there at once, and goes again
/// once the pointer is back in the game, as in other full-screen apps.
///
/// AppKit does that only when macOS hides the menu bar in full screen; with
/// "show the menu bar" on, it keeps the menu bar and the title bar (a window
/// of its own, NSToolbarFullScreenWindow) over the game for good. So the
/// menu bar stays away through the presentation options, and the title bar's
/// window shows by its alpha. Bringing the menu bar down with it, as Avo did,
/// left the title bar to AppKit's menu bar reveal, which waits for the pointer
/// to rest at the top edge: the bar came down only sometimes (the user,
/// 2026-10-25). Where AppKit keeps the title bar off the screen while the
/// menu bar is away (macOS hiding the menu bar in full screen), AppKit's own
/// reveal brings both instead. While the mouse is locked for aiming the
/// pointer stays put, so nothing comes down. Each change is logged
/// (com.avodroid, FullScreenBars).
@MainActor
public final class FullScreenBars {
    /// Over the game: no menu bar, no Dock; the title bar by its alpha.
    public static let hidden: NSApplication.PresentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
    /// AppKit's own full screen: what another app gets while this one is in
    /// the back (Avo #11), and the reveal where AppKit keeps the title bar off
    /// the screen.
    public static let system: NSApplication.PresentationOptions = [.fullScreen, .autoHideDock, .autoHideMenuBar]
    /// How close to the top the pointer brings the bar, and how far below it
    /// takes it away again (the menu bar and the title bar are about 62 pt).
    static let revealEdge: CGFloat = 2
    static let concealDistance: CGFloat = 90

    private weak var window: NSWindow?
    /// The bar is down (`show`).
    public private(set) var isShown = false
    /// AppKit's reveal brings it down (its title bar was off the screen).
    private var systemReveal = false
    /// AppKit's full-screen animation runs: the pointer brings nothing down.
    public var inTransition = false
    /// The mouse is locked for aiming: the pointer brings nothing down.
    public var pointerLocked: () -> Bool = { false }
    /// Something under the bar keeps it down while it shows (Avo's Quick
    /// Settings); a haze menu always does.
    public var keepsShown: () -> Bool = { false }
    /// Runs as the bar comes down, with its full-screen layout (Avo fits the
    /// title bar's sides).
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

    /// The title bar's own window while in full screen.
    private var titlebar: NSWindow? {
        guard let bar = window?.standardWindowButton(.closeButton)?.window, bar !== window else { return nil }
        return bar
    }

    // MARK: The window's full screen

    /// What `window(_:willUseFullScreenPresentationOptions:)` returns: the
    /// bars start out of the game.
    public var presentationOptions: NSApplication.PresentationOptions { Self.hidden }

    /// `windowDidEnterFullScreen`: the bar goes, and the pointer at the top
    /// brings it.
    public func entered() {
        show(false)
        watch(true)
    }

    /// `windowWillExitFullScreen`: the bar is the window's again.
    public func leaving() {
        watch(false)
        isShown = true
        systemReveal = false
        titlebar?.ignoresMouseEvents = false
        titlebar?.alphaValue = 1
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
        NSApp.presentationOptions = isShown && systemReveal ? Self.system : Self.hidden
    }

    // MARK: Showing

    private func show(_ shown: Bool) {
        guard let window, inFullScreen else { return }
        isShown = shown
        // The bar's window has its full-screen layout by now.
        if shown { willShow() }
        let bar = titlebar
        bar?.ignoresMouseEvents = !shown
        bar?.alphaValue = shown ? 1 : 0
        systemReveal = shown && !(bar.map { Self.isOnScreen($0, window.screen) } ?? false)
        let options = systemReveal ? Self.system : Self.hidden
        // The same options again would set AppKit's title bar animation going for nothing.
        if NSApp.presentationOptions != options { NSApp.presentationOptions = options }
        barsLogger.info("""
            bar \(shown ? "down" : "up", privacy: .public): title bar \(Self.describe(bar), privacy: .public), \
            AppKit's reveal \(self.systemReveal, privacy: .public), options \(NSApp.presentationOptions.rawValue, privacy: .public)
            """)
        if !shown { keepHidden() }
    }

    /// Most of the title bar's window is on `screen` (not moved up out of it).
    static func isOnScreen(_ bar: NSWindow, _ screen: NSScreen?) -> Bool {
        guard let screen, bar.frame.height > 0 else { return false }
        return bar.frame.intersection(screen.frame).height >= bar.frame.height / 2
    }

    private static func describe(_ bar: NSWindow?) -> String {
        guard let bar else { return "none" }
        return "\(NSStringFromRect(bar.frame)) alpha \(bar.alphaValue)"
    }

    /// AppKit animates the title bar's window after a change and leaves it
    /// opaque: hide it again once that is over.
    private func keepHidden() {
        for delay in [0.15, 0.4, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.hideAgain() }
            }
        }
    }

    private func hideAgain() {
        guard !isShown, inFullScreen, let bar = titlebar, bar.alphaValue != 0 || !bar.ignoresMouseEvents else { return }
        barsLogger.info("bar showed again by itself: \(Self.describe(bar), privacy: .public)")
        bar.alphaValue = 0
        bar.ignoresMouseEvents = true
    }

    // MARK: The pointer

    /// Follows the pointer in full screen: the top edge brings the bar,
    /// moving back down into the game takes it away.
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
        } else if !isShown, let bar = titlebar, bar.alphaValue != 0 {
            hideAgain()
        }
    }
}
