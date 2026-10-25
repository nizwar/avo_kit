import AppKit
import AvoKeymap
import AvoKitResources

/// The key mapping editor over a game (spec §5: "Tekan Cmd+Shift+K di
/// jendela game untuk membuka editor overlay transparan"). It is a view on
/// top of the game inside the game's own window, not a window of its own,
/// so it always has the window's size and place, and other apps' windows
/// cover it like they cover the game. The editing itself is KeymapEditorView.
///
/// Its panel stands beside the window, in a window of its own
/// (KeymapSidePanel), so the game keeps its whole size while controls are
/// placed on it: on the right when the screen has room there, else on the
/// left, else the window moves over a little as the editor opens (and back
/// as it closes, unless it was moved meanwhile). In full screen, or on a
/// screen too narrow even then, it is inside, beside the game, which moves
/// over for it. While the player resizes or moves the window, the panel
/// keeps its side (out of sight where it no longer fits) and is placed
/// again once the window is let go, so neither it nor the game jumps.
@MainActor
final class KeymapOverlay {
    private let editor: KeymapEditorView
    private weak var window: NSWindow?
    /// The app's screen, which the editor covers (not the Phone app bar
    /// style's frame around it).
    private weak var screen: NSView?
    private weak var focusBefore: NSResponder?
    /// The panel's window, while the panel stands outside.
    private let side = KeymapSidePanel()
    private var observers: [NSObjectProtocol] = []
    /// The window moved over to make room for the panel: from where, to where.
    private var moved: (from: NSRect, to: NSRect)?
    /// Its own move is under way: not one by the user.
    private var moving = false
    /// The panel's side beside the window (true: the right), nil while it is inside.
    private var sideRight: Bool?
    /// Waits for the window to stop moving before the panel's side is chosen again.
    private var settle: Timer?
    /// The window's least content size before the panel went inside, which widens it.
    private var minimumBefore: NSSize?
    private var screenObserver: NSObjectProtocol?
    var onClose: (() -> Void)?
    /// The panel went inside the window (true: the game moves over for it)
    /// or outside (false).
    var onPanelInside: ((Bool) -> Void)?

    /// Between the window and the panel beside it.
    private static let gap: CGFloat = 8
    /// The panel is at least this tall beside a short window, when the screen has room.
    private static let minimumHeight: CGFloat = 560
    /// The game keeps at least this much width beside the panel inside the window.
    private static let minimumGameWidth: CGFloat = 120
    /// How long the window rests before a move counts as done.
    private static let settleDelay: TimeInterval = 0.3

    var isEditing: Bool { editor.superview != nil }

    init(window: NSWindow, view: any KeymapDisplay, package: String, profile: KeymapProfile?,
         onSave: @escaping (KeymapProfile) -> String?) {
        editor = KeymapEditorView(displayRect: { [weak view] in view?.displayRect ?? .zero },
                                  profile: profile ?? KeymapProfile(package: package, name: String(localized: "My layout", bundle: .avoSharedKit), controls: []),
                                  onSave: onSave)
        self.window = window
        screen = view.superview
        editor.onClose = { [weak self] in self?.close() }
    }

    func show() {
        guard let window, let content = screen ?? window.contentView, !isEditing else { return }
        editor.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(editor, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            editor.topAnchor.constraint(equalTo: content.topAnchor),
            editor.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        focusBefore = window.firstResponder
        window.makeFirstResponder(editor)
        let center = NotificationCenter.default
        // The panel follows the window: its size, its screen, full screen.
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowChanged(name) }
            })
        }
        // Out of the window's way before full screen's animation.
        observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.putPanelInside() }
        })
        // Into the Dock with the window, and back beside it after.
        observers.append(center.addObserver(forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideSide() }
        })
        observers.append(center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placePanel(opening: false) }
        })
        // A display added, taken away or rearranged.
        screenObserver = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placePanel(opening: false) }
        }
        placePanel(opening: true)
    }

    func close() {
        guard isEditing else { return }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        settle?.invalidate()
        settle = nil
        restoreMinimumSize()
        hideSide()
        editor.movePanel(into: nil)
        editor.removeFromSuperview()
        // Back where it was, unless it was moved meanwhile.
        if let moved, let window, window.frame == moved.to, !window.styleMask.contains(.fullScreen) {
            window.setFrame(moved.from, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        moved = nil
        if let window, let focusBefore { window.makeFirstResponder(focusBefore) }
        onClose?()
    }

    /// Cancel, as ⇧⌘K again asks: changes go only once the player says so.
    func cancel() {
        editor.cancel()
    }

    /// The window is closing: see KeymapEditorView.mayClose.
    func mayClose(answer: @escaping @MainActor (Bool) -> Void) -> Bool {
        editor.mayClose(answer: answer)
    }

    /// A message for the player, in the panel's status line while the editor covers the window.
    func showNotice(_ text: String) {
        editor.showNotice(text)
    }

    /// Key presses routed here while the editor is open.
    func assign(_ trigger: Trigger, down: Bool) -> Bool {
        if down { editor.assign(trigger) }
        return true
    }

    // MARK: The panel beside the window

    private func windowChanged(_ name: Notification.Name) {
        guard !moving, let window else { return }
        switch name {
        case NSWindow.didMoveNotification:
            // Moved by the user: it stays where they put it.
            if let moved, window.frame != moved.to { self.moved = nil }
            // The panel moves with it, as a child window; out of sight while
            // off the screen, and its side chosen again once the window rests.
            if side.parent != nil, !Self.screens.contains(where: { $0.contains(side.frame) }) { hideSide() }
            settleSoon()
        case NSWindow.didResizeNotification where window.inLiveResize:
            followLiveResize()
        default:
            placePanel(opening: false)
        }
    }

    /// The window is being resized by the player: the panel keeps its side,
    /// beside the window where it fits and out of sight where it does not;
    /// inside, it stays inside. The side is chosen again at the end.
    private func followLiveResize() {
        guard let window, let right = sideRight else { return }
        if let frame = Self.sideFrame(beside: window.frame, content: screenFrame, right: right, screens: Self.screens,
                                      width: KeymapEditorView.panelWidth, gap: Self.gap, minimumHeight: Self.minimumHeight) {
            showSide(at: frame)
        } else {
            hideSide()
        }
    }

    /// Places the panel once the window has stopped moving for a moment.
    private func settleSoon() {
        settle?.invalidate()
        settle = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, !window.inLiveResize else { return }
                self.placePanel(opening: false)
            }
        }
    }

    /// Beside the window when a screen has room: on the right, else on the
    /// left, else (`opening`) the window moves over so it fits on the right.
    /// Inside, beside the game, in full screen or without room even then.
    private func placePanel(opening: Bool) {
        guard let window, isEditing else { return }
        guard !window.styleMask.contains(.fullScreen), let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            putPanelInside()
            return
        }
        let width = KeymapEditorView.panelWidth
        func beside(_ frame: NSRect, right: Bool) -> NSRect? {
            Self.sideFrame(beside: frame, content: screenFrame(for: frame), right: right, screens: Self.screens, width: width, gap: Self.gap,
                           minimumHeight: Self.minimumHeight)
        }
        if let frame = beside(window.frame, right: true) {
            showSide(at: frame, right: true)
        } else if let frame = beside(window.frame, right: false) {
            showSide(at: frame, right: false)
        } else if opening, window.frame.width + Self.gap + width <= visible.width {
            var frame = window.frame
            let from = frame
            frame.origin.x = visible.maxX - width - Self.gap - frame.width
            moving = true
            window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            moving = false
            moved = (from, window.frame)
            if let besideFrame = beside(window.frame, right: true) {
                showSide(at: besideFrame, right: true)
            } else {
                putPanelInside()
            }
        } else {
            putPanelInside()
        }
    }

    /// The displays' usable parts: the panel may stand on the one beside the window's.
    private static var screens: [NSRect] { NSScreen.screens.map(\.visibleFrame) }

    /// Where the game's screen is, in screen coordinates (inside the Phone
    /// app bar style's frame around it): the panel's top lines up with it.
    private var screenFrame: NSRect? { screenFrame(for: nil) }

    /// The game's screen for the window at `frame` (it keeps its place in the window).
    private func screenFrame(for frame: NSRect?) -> NSRect? {
        guard let window, let screen, screen.window === window else { return nil }
        let now = window.convertToScreen(screen.convert(screen.bounds, to: nil))
        guard let frame else { return now }
        return now.offsetBy(dx: frame.minX - window.frame.minX, dy: frame.minY - window.frame.minY)
    }

    /// The panel's frame beside `window` on one side, if a display has room
    /// for it there (the window's own, or the one beside it): from the
    /// game's screen's top (`content`, else the window's), as tall as it (or
    /// as `minimumHeight`, beside a short one), and never a sliver.
    static func sideFrame(beside window: NSRect, content: NSRect?, right: Bool, screens: [NSRect], width: CGFloat, gap: CGFloat,
                          minimumHeight: CGFloat) -> NSRect? {
        let x = right ? window.maxX + gap : window.minX - gap - width
        let reference = content ?? window
        for visible in screens where x >= visible.minX && x + width <= visible.maxX {
            let top = min(reference.maxY, visible.maxY)
            let height = min(max(reference.height, minimumHeight), visible.height)
            let bottom = max(top - height, visible.minY)
            guard top - bottom >= Self.shortest else { continue }
            return NSRect(x: x, y: bottom, width: width, height: top - bottom)
        }
        return nil
    }

    /// The shortest the panel stands beside the window.
    static let shortest: CGFloat = 200

    private func showSide(at frame: NSRect, right: Bool? = nil) {
        guard let window else { return }
        if let right { sideRight = right }
        restoreMinimumSize()
        if side.parent == nil {
            editor.movePanel(into: side.host)
            onPanelInside?(false)
            // It slides out from behind the window's edge.
            let fromRight = frame.minX >= window.frame.maxX
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            side.alphaValue = 0
            side.setFrame(reduceMotion ? frame : frame.offsetBy(dx: fromRight ? -16 : 16, dy: 0), display: false)
            window.addChildWindow(side, ordered: .above)
            side.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                side.animator().alphaValue = 1
                side.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.side.invalidateShadow() }
            }
        } else if side.frame != frame {
            side.setFrame(frame, display: true)
            side.invalidateShadow()
        }
    }

    private func putPanelInside() {
        hideSide()
        sideRight = nil
        editor.movePanel(into: nil)
        makeRoomInside()
        onPanelInside?(true)
    }

    /// Inside, the panel takes its width from the game: the window is at
    /// least that much wider than the game's narrowest, and grows to it now
    /// when it is narrower (not in full screen).
    private func makeRoomInside() {
        guard let window, !window.styleMask.contains(.fullScreen), let content = window.contentView else { return }
        let needed = KeymapEditorView.panelWidth + Self.minimumGameWidth
        if minimumBefore == nil { minimumBefore = window.contentMinSize }
        window.contentMinSize.width = max(minimumBefore?.width ?? 0, needed)
        let missing = needed - content.bounds.width
        guard missing > 0 else { return }
        var frame = window.frame
        frame.size.width += missing
        if let visible = window.screen?.visibleFrame, frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
        moving = true
        window.setFrame(frame, display: true)
        moving = false
    }

    /// The window's least size as it was, once the panel is out of it.
    private func restoreMinimumSize() {
        guard let before = minimumBefore, let window else { return }
        window.contentMinSize = before
        minimumBefore = nil
    }

    private func hideSide() {
        side.parent?.removeChildWindow(side)
        side.orderOut(nil)
    }
}

/// The key mapping editor's panel in a window of its own, beside the game's
/// window and a child of it: it moves with the window, and minimizes and
/// goes to the back with it. It takes the keyboard only for a field (a
/// mode's name), so keys otherwise stay with the editor over the game.
final class KeymapSidePanel: NSPanel {
    /// The editor's panel goes in here (it draws its rounded card itself).
    let host = NSView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: KeymapEditorView.panelWidth, height: 560),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The shadow follows the card's rounded corners.
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = host
    }

    // A mode's name is typed here.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
