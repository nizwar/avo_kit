import AppKit
import AvoKeymap
import AvoKitResources
import AvoInput
import GameController

/// Runs the keymapping profile for one window (spec §5 and §5a): keys,
/// mouse buttons and gamepads become touches, FPS mode captures the pointer
/// and reads raw mouse movement, MOBA controls aim at the free cursor.
/// Avo's app windows and Avo Hub's mirror windows each run one, over their
/// game view (KeymapDisplay) and their own store (KeymapStore).
@MainActor
public final class KeymapController {
    private let package: String
    private let displayID: UInt32
    private weak var view: (any KeymapDisplay)?
    private let send: (InputRecord) -> Void
    private let store: KeymapStore
    /// How far the engine's touches spread (`init(touchSpread:)`).
    private let touchSpread: Double
    public private(set) var profile: KeymapProfile?
    private var engine: KeymapEngine?
    private var displayLink: CADisplayLink?
    /// The controllers' changes, from GamepadHub.
    private var gamepadListener: UUID?
    private var overlay: KeymapOverlay?
    public private(set) var isPointerLocked = false
    /// While the pointer is locked: GameController's mouse notifications.
    private var mouseObservers: [any NSObjectProtocol] = []
    /// When raw motion last came from a mouse GameController sees.
    private var rawMotionAt: CFTimeInterval = 0
    /// This lock, the mouse moved without raw motion: its events count at once.
    private var eventMotionOnly = false
    /// A locked mouse's event motion, held until raw motion would have come
    /// (then it was the same movement, counted once).
    private var heldMotion: (dx: Double, dy: Double, since: CFTimeInterval)?
    /// The profile has MOBA controls, which need to know where the cursor is.
    private var aimsAtCursor = false
    /// The keyboard's and the mouse's state now, beside their events (tests give their own).
    var hardware = Hardware()
    /// The presses the hardware showed down as their event came: only these are let go by what it says
    /// later (a press it never showed, such as a trackpad's tap, is left to its own release).
    private var seenDown: Set<Trigger> = []
    /// The click's finger went down with the left button seen down.
    private var clickSeenDown = false
    /// When the held keys were last checked against the hardware (`releaseUnseen`).
    private var lastReleaseCheck: CFTimeInterval = 0
    /// What `releaseUnseen` let go: its late release, should it still come, is swallowed.
    private var letGoUnseen: Set<Trigger> = []
    /// Short messages for the window (mouse locked or freed). While the
    /// editor is open they show in its panel instead (it covers the window's).
    public var onNotice: ((String) -> Void)?
    /// The layout's mode changed (a Switch Mode control, a new layout): its id.
    public var onMode: ((String?) -> Void)?
    /// The mode the layout is in now; nil without modes.
    public var mode: String? { engine?.mode }
    /// The profile in use changed (loaded, saved, imported).
    public var onProfile: ((KeymapProfile?) -> Void)?
    /// The editor opened (true) or closed (false).
    public var onEditing: ((Bool) -> Void)?
    /// The editor's panel went inside the window (true: the game moves over
    /// for it) or beside it, outside (false). KeymapOverlay decides.
    public var onPanelInside: ((Bool) -> Void)?
    /// Game Mode turned on or off.
    public var onGameMode: ((Bool) -> Void)?
    /// The editor took the controller or gave it back (`takesGamepad`), for
    /// whoever hands it to Android (Avo's GamepadForwarder).
    public var onGamepadOwner: (() -> Void)?

    /// Game Mode (⌘G): the key mapping is in charge. Off, every key and
    /// click reaches the app as it is. Remembered per app (KeymapStore).
    public private(set) var gameMode: Bool

    public func setGameMode(_ on: Bool) {
        guard on != gameMode else { return }
        gameMode = on
        store.setGameMode(on)
        // Nothing stays pressed or locked when the mapping lets go.
        if !on { focusLost() }
        updateTicking()
        onGameMode?(on)
        guard profile != nil else {
            // Nothing to map yet: the button alone would light up and do nothing.
            if on { notice(String(localized: "This app has no key mapping yet. Press ⇧⌘K to set one up.", bundle: .avoSharedKit)) }
            return
        }
        notice(on ? String(localized: "Game Mode on: the key mapping is active. ⌘G turns it off.", bundle: .avoSharedKit)
                     : String(localized: "Game Mode off: keys and clicks go to the app. ⌘G turns it on.", bundle: .avoSharedKit))
    }

    /// The mapping takes input only in Game Mode and outside the editor.
    private var mapping: Bool { gameMode && engine != nil && overlay?.isEditing != true }

    /// Game Mode with a profile that binds the gamepad: its buttons and
    /// sticks become touches, and Android gets no gamepad (GamepadForwarder).
    /// The editor holds it too, while its buttons are being bound.
    public var takesGamepad: Bool { (gameMode && profile?.usesGamepad == true) || overlay?.isEditing == true }

    /// The key that locks the mouse for the eye, when the profile has one.
    public var mouseLockKey: String? { profile?.fps?.cursorToggle.shortLabel }

    /// The editor's panel's width: inside the window, the game's picture
    /// moves over for it (`onPanelInside`).
    public static var editorPanelWidth: CGFloat { KeymapEditorView.panelWidth }

    /// - Parameter touchSpread: how far the mapping's touches spread from the
    ///   points its controls aim at (`KeymapEngine(touchSpread:)`): 1, the
    ///   default, lands like a finger; 0 touches the exact points, for tests.
    public init(package: String, displayID: UInt32, view: any KeymapDisplay, store: KeymapStore, touchSpread: Double = 1,
                send: @escaping (InputRecord) -> Void) {
        self.package = package
        self.displayID = displayID
        self.view = view
        self.send = send
        self.store = store
        self.touchSpread = touchSpread
        gameMode = store.gameMode()
        load()
        gamepadListener = GamepadHub.shared.addListener { [weak self] inputs, _ in self?.gamepad(inputs) }
    }

    /// The user's profile wins over the community profile shipped with Avo.
    /// The window decides whether the app is a game by the same lookup, so
    /// its graphics profile and the key mapping always agree.
    private func load() {
        if let usable = store.usable() { apply(usable.profile) }
    }

    public func apply(_ profile: KeymapProfile?) {
        if var engine { emit(engine.reset()); self.engine = engine }
        letGoUnseen.removeAll()
        seenDown.removeAll()
        clickSeenDown = false
        unlockPointer()
        self.profile = profile
        aimsAtCursor = profile?.controls.contains(where: \.followsCursor) == true
        guard let profile, let view else {
            engine = nil
            updateTicking()
            onProfile?(nil)
            onMode?(nil)
            return
        }
        let size = view.displaySize
        // The game is where it was: the layout stays in its mode, its scroll bars' thumbs where they are.
        engine = KeymapEngine(profile: profile, displayID: displayID, width: size.width, height: size.height,
                              touchSpread: touchSpread, continuing: engine)
        updateTicking()
        onProfile?(profile)
        onMode?(engine?.mode)
    }

    public func save(_ profile: KeymapProfile) throws {
        try FileManager.default.createDirectory(at: store.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try profile.encoded()
        try data.write(to: store.profileURL, options: .atomic)
        // Use what is on disk now: saving dropped any controls from a newer
        // Avo, and the editor must not warn about them when it opens again.
        apply(try KeymapProfile.decode(data))
        // Just set up: ready to play.
        setGameMode(true)
    }

    // MARK: Input from the game view (returns true when consumed)

    public func key(_ key: KeyName, down: Bool, isRepeat: Bool) -> Bool {
        if overlay?.isEditing == true { return overlay?.assign(.key(key), down: down) ?? false }
        guard mapping else { return false }
        // A held key's repeats are the mapping's when its press was: the
        // mouse lock's key too, or the game would get them (and never their keyUp).
        guard !isRepeat else {
            guard let profile = engine?.profile else { return false }
            return profile.fps?.cursorToggle == .key(key) || profile.controls.contains { $0.allTriggers.contains(.key(key)) }
        }
        if !down, letGoUnseen.remove(.key(key)) != nil { return true }
        if down {
            letGoUnseen.remove(.key(key))
            reportCursor()
            if let code = KeyboardMapping.macKeyCode(for: key), hardware.isKeyDown(code) { seenDown.insert(.key(key)) }
        } else {
            seenDown.remove(.key(key))
        }
        return handle(down ? .keyDown(key) : .keyUp(key))
    }

    public func mouse(_ button: MouseButton, down: Bool) -> Bool {
        // The mouse locks only with the eye's key: a click is a click.
        guard mapping else { return false }
        if !down, letGoUnseen.remove(.mouse(button)) != nil { return true }
        let seen = hardware.mouseButtons() & (1 << button.buttonNumber) != 0
        if down {
            letGoUnseen.remove(.mouse(button))
            reportCursor()
            if seen { seenDown.insert(.mouse(button)) }
            if button == .left { clickSeenDown = seen }
        } else {
            seenDown.remove(.mouse(button))
            if button == .left { clickSeenDown = false }
        }
        if handle(down ? .mouseDown(button) : .mouseUp(button)) { return true }
        // A left click no control takes is a touch where it happens. It goes
        // in with the engine's touches: sent on its own (the game view's
        // PointerTranslator) it would also claim pointer 0, and Android would
        // drop a touch a key is holding, such as the MOBA joystick.
        guard button == .left, let p = clickLocation() else { return false }
        return handle(down ? .fingerDown(x: p.x, y: p.y) : .fingerUp(x: p.x, y: p.y))
    }

    /// Cursor movement in display pixels; true when an anchor tap took it.
    public func pointerMoved(dx: Double, dy: Double) -> Bool {
        guard mapping else { return false }
        return handle(.pointerMoved(dx: dx, dy: dy))
    }

    /// A scroll over the game; true when the mapping took it, and the game
    /// gets none of it. A mouse wheel's event is one notch. A trackpad or a
    /// Magic Mouse scrolls by points: they add up to a notch every
    /// `trackpadNotch`, and its momentum after the fingers lift counts for
    /// nothing. Such a gesture is the mapping's or the game's as a whole.
    public func scroll(_ event: NSEvent) -> Bool {
        scroll(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, phase: event.phase, momentum: event.momentumPhase)
    }

    /// The points of trackpad scrolling that make one wheel notch.
    static let trackpadNotch = 40.0
    /// The trackpad's scrolling not a notch yet, in points (its sign the way it goes).
    private var trackpadRest = 0.0
    /// Whether the mapping takes the trackpad gesture going on, its momentum
    /// included, as decided when it began; nil between gestures.
    private var trackpadTaken: Bool?

    func scroll(deltaY: Double, precise: Bool, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = []) -> Bool {
        let begins = phase.contains(.began) || phase.contains(.mayBegin)
        guard mapping, let engine else {
            // Begun while the mapping is off, the gesture is the game's to its
            // end, even if Game Mode comes on midway (its finger needs its end).
            if precise, begins { trackpadTaken = false }
            return false
        }
        guard precise else { return deltaY != 0 && handle(.scroll(dy: deltaY)) }
        if phase.isEmpty && momentum.isEmpty {
            // A source without phases (a smooth-scrolling mouse utility): each
            // event on its own, its points still adding up to notches.
            trackpadTaken = engine.takes(.scrollUp) || engine.takes(.scrollDown)
        } else if trackpadTaken == nil || begins {
            trackpadTaken = engine.takes(.scrollUp) || engine.takes(.scrollDown)
            trackpadRest = 0
        }
        let taken = trackpadTaken == true
        // The decision lasts through the fling after the fingers lift.
        defer {
            if [.ended, .cancelled].contains(where: { momentum.contains($0) }) { trackpadTaken = nil }
        }
        guard taken, momentum.isEmpty, deltaY != 0 else { return taken }
        // Turned the other way: from nothing again.
        if trackpadRest != 0, (trackpadRest > 0) != (deltaY > 0) { trackpadRest = 0 }
        trackpadRest += deltaY
        while abs(trackpadRest) >= Self.trackpadNotch {
            let notch: Double = trackpadRest > 0 ? 1 : -1
            trackpadRest -= notch * Self.trackpadNotch
            _ = handle(.scroll(dy: notch))
        }
        return true
    }

    public func resize(width: Double, height: Double) {
        guard var engine else { return }
        emit(engine.resize(width: width, height: height))
        self.engine = engine
    }

    public func focusLost() {
        unlockPointer()
        letGoUnseen.removeAll()
        seenDown.removeAll()
        clickSeenDown = false
        guard var engine else { return }
        emit(engine.reset())
        self.engine = engine
    }

    // MARK: Releases that never came

    /// The keyboard's and the mouse's state, read beside their events.
    @MainActor
    struct Hardware {
        /// Whether the key with this Mac key code is down now (the session's HID state).
        var isKeyDown: (UInt16) -> Bool = { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
        /// The mouse buttons down now, one bit per `MouseButton.buttonNumber`.
        var mouseButtons: () -> Int = { NSEvent.pressedMouseButtons }
    }

    /// How often the held keys and buttons are checked while the mapping ticks.
    static let releaseCheckInterval: CFTimeInterval = 0.1

    /// A key or button the engine still holds that the hardware has let go is
    /// released now, so nothing stays pressed in the game: its keyUp went
    /// elsewhere (a trackpad gesture of the system's, Mission Control, an
    /// input method, a menu that took the keyboard for a moment).
    func releaseUnseen(at now: CFTimeInterval) {
        guard now - lastReleaseCheck >= Self.releaseCheckInterval, mapping, let held = engine?.heldTriggers else { return }
        lastReleaseCheck = now
        let buttons = hardware.mouseButtons()
        seenDown.formIntersection(held)
        for trigger in held where seenDown.contains(trigger) {
            let released: Bool
            switch trigger {
            case .key(let key):
                guard let code = KeyboardMapping.macKeyCode(for: key) else { continue }
                released = !hardware.isKeyDown(code)
            case .mouse(let button):
                released = buttons & (1 << button.buttonNumber) == 0
            default:
                continue
            }
            guard released else { continue }
            seenDown.remove(trigger)
            letGoUnseen.insert(trigger)
            switch trigger {
            case .key(let key): _ = handle(.keyUp(key))
            case .mouse(let button): _ = handle(.mouseUp(button))
            default: break
            }
        }
        // A click (its finger, or what its click zone pressed), its button up without a mouseUp.
        if clickSeenDown, engine?.isClickDown == true, buttons & 1 == 0 {
            clickSeenDown = false
            letGoUnseen.insert(.mouse(.left))
            let at = cursorInDisplay() ?? (0, 0)
            _ = handle(.fingerUp(x: at.x, y: at.y))
        }
    }

    public func stop() {
        focusLost()
        stopTicking()
        if let gamepadListener { GamepadHub.shared.removeListener(gamepadListener) }
        gamepadListener = nil
        overlay?.close()
    }

    private func handle(_ input: KeymapEngine.Input) -> Bool {
        run(input)?.consumed ?? false
    }

    /// The engine's answer to `input`, its touches sent, the mode and the
    /// mouse lock followed; nil without an engine.
    @discardableResult
    private func run(_ input: KeymapEngine.Input) -> KeymapEngine.Output? {
        guard var engine else { return nil }
        let output = engine.handle(input, at: CACurrentMediaTime())
        self.engine = engine
        emit(output.events)
        if let mode = output.mode {
            onMode?(mode)
            if let name = profile?.modes.first(where: { $0.id == mode })?.name {
                notice(String(localized: "Mode: \(name)", bundle: .avoSharedKit))
            }
        }
        if let lock = output.pointerLock {
            if lock { lockPointer() } else { unlockPointer() }
        }
        return output
    }

    private func emit(_ events: [TouchEvent]) {
        for event in events { send(.touch(event)) }
    }

    // MARK: Cursor (MOBA controls)

    /// Tells the engine where the cursor is before a press, so a MOBA
    /// control aims the right way from its first frame.
    private func reportCursor() {
        guard aimsAtCursor, !isPointerLocked, let cursor = cursorInDisplay() else { return }
        _ = handle(.cursor(x: cursor.x, y: cursor.y))
    }

    /// The cursor in display pixels, not clamped to the display: beyond the
    /// game's edge it still gives a direction.
    private func cursorInDisplay() -> (x: Double, y: Double)? {
        guard let window = view?.window else { return nil }
        return inDisplay(window.mouseLocationOutsideOfEventStream)
    }

    /// Where the left click being handled happened, in display pixels (the
    /// cursor may have moved on since), else where the cursor is now.
    private func clickLocation() -> (x: Double, y: Double)? {
        guard let window = view?.window else { return nil }
        if let event = NSApp.currentEvent, event.window === window, [.leftMouseDown, .leftMouseUp].contains(event.type) {
            return inDisplay(event.locationInWindow)
        }
        return cursorInDisplay()
    }

    private func inDisplay(_ locationInWindow: NSPoint) -> (x: Double, y: Double)? {
        guard let view else { return nil }
        let rect = view.displayRect, size = view.displaySize
        guard rect.width > 0, rect.height > 0 else { return nil }
        var point = view.convert(locationInWindow, from: nil)
        // displayRect is measured from the bottom left, as an unflipped view is.
        if view.isFlipped { point.y = view.bounds.height - point.y }
        return ((point.x - rect.minX) / rect.width * size.width, (rect.maxY - point.y) / rect.height * size.height)
    }

    // MARK: Timing

    /// The engine ticks on every display refresh only while it can act:
    /// Game Mode on with a profile. Off, the engine is reset (nothing held,
    /// nothing scheduled) and the main thread has nothing to do per frame.
    /// The controller editor's live view does not need it (GamepadHub).
    private func updateTicking() {
        if gameMode && engine != nil { startTicking() } else { stopTicking() }
    }

    private func startTicking() {
        guard displayLink == nil, let view else { return }
        let link = view.displayLink(target: TickTarget { [weak self] in self?.tick() }, selector: #selector(TickTarget.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if isPointerLocked { flushHeldMotion(at: now) }
        releaseUnseen(at: now)
        // The editor has the keys (the engine was reset as it opened): nothing to do.
        guard mapping, var engine else { return }
        // A held MOBA control or click reads the cursor on every frame: while
        // a mouse button is down macOS sends drags, which never reach pointerMoved.
        if engine.isFollowingCursor, !isPointerLocked, let cursor = cursorInDisplay() {
            emit(engine.handle(.cursor(x: cursor.x, y: cursor.y), at: now).events)
        }
        emit(engine.tick(at: now))
        self.engine = engine
    }

    // MARK: Pointer lock (FPS mode)

    private func lockPointer() {
        guard !isPointerLocked, let view, let window = view.window else { return }
        isPointerLocked = true
        if let toggle = engine?.profile.fps?.cursorToggle.shortLabel {
            notice(String(localized: "Mouse locked for aiming. Press \(toggle) to free it.", bundle: .avoSharedKit))
        }
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
        // Park the hidden cursor over the window so clicks keep landing here.
        let center = window.convertPoint(toScreen: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
        if let screen = window.screen {
            CGWarpMouseCursorPosition(CGPoint(x: center.x, y: screen.frame.maxY - center.y))
        }
        // Raw, unaccelerated deltas (spec §5a: "gerakan mouse mentah").
        listenToMice()
        if var engine {
            emit(engine.setPointerLocked(true))
            self.engine = engine
        }
    }

    private func unlockPointer() {
        guard isPointerLocked else { return }
        isPointerLocked = false
        if let toggle = engine?.profile.fps?.cursorToggle.shortLabel {
            notice(String(localized: "Mouse free. Press \(toggle) to aim with it.", bundle: .avoSharedKit))
        }
        stopListeningToMice()
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        if var engine {
            emit(engine.setPointerLocked(false))
            self.engine = engine
        }
    }

    // Raw motion while the pointer is locked: from every mouse GameController
    // sees (GCMouse.current is only the one that moved last, so a second
    // mouse, or a trackpad used before it, went unheard), and for a mouse it
    // does not see (some wireless receivers) from the window's mouse events,
    // which stand in while no raw motion comes.

    private func listenToMice() {
        for mouse in GCMouse.mice() { listen(to: mouse) }
        mouseObservers = [Notification.Name.GCMouseDidConnect, .GCMouseDidBecomeCurrent].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isPointerLocked else { return }
                    for mouse in GCMouse.mice() { self.listen(to: mouse) }
                }
            }
        }
    }

    private func listen(to mouse: GCMouse) {
        mouse.mouseInput?.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated { self?.rawMotion(dx: Double(dx), dy: Double(-dy)) }
        }
    }

    private func stopListeningToMice() {
        for mouse in GCMouse.mice() { mouse.mouseInput?.mouseMovedHandler = nil }
        for observer in mouseObservers { NotificationCenter.default.removeObserver(observer) }
        mouseObservers = []
        heldMotion = nil
        eventMotionOnly = false
    }

    private func rawMotion(dx: Double, dy: Double) {
        rawMotionAt = CACurrentMediaTime()
        // What the window's events said meanwhile was this same movement.
        heldMotion = nil
        eventMotionOnly = false
        _ = handle(.mouseMoved(dx: dx, dy: dy))
    }

    /// The window's mouse motion while the pointer is locked (the game
    /// view): it counts for a mouse GameController does not see.
    public func lockedMotion(dx: Double, dy: Double) {
        guard isPointerLocked, mapping, dx != 0 || dy != 0 else { return }
        let now = CACurrentMediaTime()
        // Raw motion is coming: this is the same movement.
        if now - rawMotionAt < 0.5 { return }
        if eventMotionOnly {
            _ = handle(.mouseMoved(dx: dx, dy: dy))
            return
        }
        let held = heldMotion
        heldMotion = (dx + (held?.dx ?? 0), dy + (held?.dy ?? 0), held?.since ?? now)
    }

    /// Event motion no raw motion followed: a mouse GameController does not
    /// see. It moves the eye, and from now on (this lock) its events at once.
    private func flushHeldMotion(at now: CFTimeInterval) {
        guard let held = heldMotion, now - held.since >= 0.05 else { return }
        heldMotion = nil
        eventMotionOnly = true
        _ = handle(.mouseMoved(dx: held.dx, dy: held.dy))
    }

    // MARK: Gamepads (GameController.framework, through GamepadHub)

    /// The controller's buttons and sticks, for the key window's mapping.
    /// With vibration on, a button that touches the screen gives a short
    /// pulse (on controllers that can).
    private func gamepad(_ inputs: [KeymapEngine.Input]) {
        guard mapping, view?.window?.isKeyWindow == true else { return }
        var touched = false
        for input in inputs {
            if case .gamepadButton(_, true) = input {
                reportCursor()
                // A finger went down (a hotkey's switch alone touches nothing).
                let output = run(input)
                touched = touched || output?.events.contains { $0.action == .down || $0.action == .pointerDown } == true
            } else {
                run(input)
            }
        }
        if touched, profile?.gamepadSettings.vibration == true { GamepadHub.shared.pulse() }
    }

    // MARK: Editor (Cmd+Shift+K)

    /// The key mapping editor is open over the window (its menu item then closes it).
    public var isEditing: Bool { overlay?.isEditing == true }

    /// Whether the window may close now (the red button, ⌘W, quitting).
    /// With the editor open and changes in it, the editor asks first (Save,
    /// Discard, Keep Editing) and this says false; `answer` then gets true
    /// once the changes are saved or discarded (close the window there) or
    /// false to keep editing. Without the editor, or without changes, true:
    /// the editor (if open) closes, and the window may close at once. A
    /// false always brings exactly one answer, later (false, when another of
    /// the editor's questions is already up), so a quit can wait for it.
    public func mayClose(answer: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard let overlay, overlay.isEditing else { return true }
        return overlay.mayClose(answer: answer)
    }

    /// Shows `text` in the editor's panel while the editor is open (true),
    /// where the window's own notices would be under it; false otherwise.
    @discardableResult
    public func showInEditor(_ text: String) -> Bool {
        guard let overlay, overlay.isEditing else { return false }
        overlay.showNotice(text)
        return true
    }

    /// A message for the player: in the editor while it is open, else the window's.
    private func notice(_ text: String) {
        if !showInEditor(text) { onNotice?(text) }
    }

    /// Opens the editor, or closes it. Its bar's Controller button brings
    /// the controller panel out (ControllerPanel.swift).
    public func toggleEditor(over window: NSWindow?) {
        guard let window, let view else { return }
        if let overlay, overlay.isEditing {
            overlay.cancel()
            return
        }
        focusLost()
        let overlay = KeymapOverlay(window: window, view: view, package: package, profile: profile) { [weak self] profile in
            do {
                try self?.save(profile)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        overlay.onClose = { [weak self] in
            self?.overlay = nil
            self?.onEditing?(false)
            self?.onGamepadOwner?()
        }
        overlay.onPanelInside = { [weak self] inside in self?.onPanelInside?(inside) }
        self.overlay = overlay
        onEditing?(true)
        overlay.show()
        // The controller is the editor's now, not Android's.
        onGamepadOwner?()
    }
}

/// CADisplayLink needs an Objective-C target.
private final class TickTarget: NSObject {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor @objc func fire() { action() }
}
