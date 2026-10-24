import Foundation

extension Bundle {
    /// Localized text of every module in avo_kit (`Resources/Localizable.xcstrings`
    /// of this target). Use it as `String(localized: "…", bundle: .avoSharedKit)`.
    ///
    /// Xcode copies package resource bundles into each app that links the
    /// package, not into a framework that links it (Avo's AvoHostKit), so the
    /// generated `Bundle.module` traps in processes that only load the
    /// framework, such as Avo's App Shims. This also looks in the app that
    /// contains the framework, and falls back to the main bundle, which shows
    /// the English source text.
    public static let avoSharedKit: Bundle = {
        let name = "avo_kit_AvoKitResources.bundle"
        let framework = Bundle(for: LocalizationAnchor.self)
        let directories: [URL?] = [
            // The app (Avo.app, AvoDaemon.app, Avo Hub.app).
            Bundle.main.resourceURL,
            // A framework or test bundle that carries its own resources.
            framework.resourceURL,
            // An App Shim: Avo.app/Contents/Frameworks/AvoHostKit.framework → Avo.app/Contents/Resources.
            framework.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources"),
            // Command-line tools and `swift test`, built next to the bundle.
            Bundle.main.bundleURL,
            framework.bundleURL.deletingLastPathComponent(),
        ]
        for case let directory? in directories {
            if let bundle = Bundle(url: directory.appending(path: name)) { return bundle }
        }
        return .main
    }()
}

private final class LocalizationAnchor {}

/// The os_log subsystem the kit logs under: Avo's, which Avo Hub shares.
public enum AvoKitLog {
    public static let subsystem = "com.avodroid"
}
