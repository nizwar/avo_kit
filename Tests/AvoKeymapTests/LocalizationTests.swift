import Foundation
import Testing
@testable import AvoKeymap

// The kit's text in Indonesian: its catalog compiled into the kit's own
// bundle (Bundle.avoSharedKit), which a host finds through the modules.

@Suite struct LocalizationTests {
    private var indonesian: Bundle? {
        Bundle.avoSharedKit.resourceURL.map { $0.appending(path: "id.lproj") }.flatMap(Bundle.init(url:))
    }

    @Test func theKitsBundleIsFoundAndHasIndonesian() throws {
        let kit = Bundle.avoSharedKit
        #expect(kit != .main, "fell back to the main bundle: English only")
        #expect(kit.bundleURL.lastPathComponent == "avo_kit_AvoKitResources.bundle")
        #expect(Set(kit.localizations).isSuperset(of: ["en", "id"]))
        let id = try #require(indonesian)
        #expect(String(localized: "Click Area", bundle: id) == "Area Klik")
        #expect(String(localized: "Clicking the game presses it", bundle: id) != "Clicking the game presses it")
    }

    /// A key with an interpolation keeps a literal % as %% (`\(name): …50%…`),
    /// one without keeps a single %: both come out with one.
    @Test func percentSignsComeOutOnce() throws {
        let id = try #require(indonesian)
        let name = "s"
        #expect(String(localized: "\(name): a step must be 1 to 50% of the track", bundle: id) == "s: langkah harus 1 sampai 50% dari jalur")
        let english = String(localized: "\(name): a step must be 1 to 50% of the track", bundle: .avoSharedKit)
        #expect(english.contains("50% of") || english.contains("50% dari"), "\(english)")
        let plain = String(localized: "Custom (\(Int(30))%)", bundle: id)
        #expect(!plain.contains("%%"), "\(plain)")
    }

    /// Every key of the catalog compiled into id.lproj with its translation.
    @Test func everyCatalogKeyHasItsIndonesianText() throws {
        let id = try #require(indonesian)
        let catalogURL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/AvoKitResources/Resources/Localizable.xcstrings")
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        var missing: [String] = []
        for (key, entry) in strings {
            let unit = ((entry["localizations"] as? [String: Any])?["id"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard let value = unit?["value"] as? String, unit?["state"] as? String == "translated" else {
                missing.append(key)
                continue
            }
            if id.localizedString(forKey: key, value: "\u{0}", table: nil) != value { missing.append(key) }
        }
        #expect(missing.isEmpty, "\(missing)")
    }
}
