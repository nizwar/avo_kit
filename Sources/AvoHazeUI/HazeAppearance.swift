import AppKit

// Which of the haze's two looks a window wears: as the Mac (System), or
// always Light or always Dark (Settings › General › Appearance in Avo and
// Avo Hub). The haze's colours (QuickHaze, HazeTheme.swift's Haze) follow a
// view's appearance, so the choice is the appearance an app gives NSApp,
// and every window and popover of it that does not set its own.

/// System, Light or Dark.
public enum HazeAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    /// What `NSApp.appearance` (a window's, a popover's) takes for it: nil
    /// follows the Mac.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension NSAppearance {
    /// Dark, or one of its kinds (high contrast, vibrant): the haze's dark look.
    public var isHazeDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// Where an app keeps its appearance, and how its other processes (Avo's
/// daemon and App Shims, Avo Hub's agent) hear of a change: a distributed
/// notification that carries the new choice.
public struct HazeAppearanceSetting: @unchecked Sendable {
    /// A UserDefaults every process of the app reads (a shared suite).
    public let store: UserDefaults
    public let key: String
    /// Posted, with the choice's raw value under `key`, when it changes.
    public let changed: Notification.Name

    public init(store: UserDefaults, key: String, changed: Notification.Name) {
        self.store = store
        self.key = key
        self.changed = changed
    }

    /// The choice: System when none is kept (or one this version does not know).
    public var appearance: HazeAppearance {
        store.string(forKey: key).flatMap(HazeAppearance.init(rawValue:)) ?? .system
    }

    /// Keeps `appearance` (System as no value, the default) and tells the
    /// app's other processes.
    public func set(_ appearance: HazeAppearance) {
        if appearance == .system { store.removeObject(forKey: key) } else { store.set(appearance.rawValue, forKey: key) }
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, userInfo: [key: appearance.rawValue],
                                                                     deliverImmediately: true)
    }

    /// Calls `apply` with the choice now, and again whenever it changes in
    /// any process of the app, for as long as the returned follower lives.
    @MainActor public func follow(_ apply: @escaping @MainActor (HazeAppearance) -> Void) -> HazeAppearanceFollower {
        HazeAppearanceFollower(setting: self, apply: apply)
    }

    /// Gives NSApp the choice now and after every change: every window of
    /// this process that does not set its own appearance wears it.
    @MainActor public func followInApp() -> HazeAppearanceFollower {
        follow { NSApp.appearance = $0.nsAppearance }
    }
}

/// Applies an app's appearance as it changes (HazeAppearanceSetting.follow).
@MainActor
public final class HazeAppearanceFollower: NSObject {
    private let setting: HazeAppearanceSetting
    private let apply: @MainActor (HazeAppearance) -> Void
    public private(set) var appearance: HazeAppearance

    init(setting: HazeAppearanceSetting, apply: @escaping @MainActor (HazeAppearance) -> Void) {
        self.setting = setting
        self.apply = apply
        appearance = setting.appearance
        super.init()
        apply(appearance)
        // A background process (a daemon, a shim behind another app) still
        // hears it at once.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed(_:)), name: setting.changed, object: nil,
                                                            suspensionBehavior: .deliverImmediately)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc nonisolated private func changed(_ notification: Notification) {
        // The notification's own value: the other process's defaults may
        // not have reached this one's yet.
        let raw = notification.userInfo?[setting.key] as? String
        Task { @MainActor in self.update(raw.flatMap(HazeAppearance.init(rawValue:)) ?? self.setting.appearance) }
    }

    private func update(_ new: HazeAppearance) {
        guard new != appearance else { return }
        appearance = new
        apply(new)
    }
}
