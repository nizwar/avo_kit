import AppKit
@testable import AvoHazeUI
import SwiftUI
import Testing

@MainActor
@Suite("The haze's two looks")
struct HazeAppearanceTests {
    /// A defaults suite of the test's own, gone afterwards.
    private func setting(_ name: String = #function) -> (HazeAppearanceSetting, UserDefaults, String) {
        let suite = "com.avodroid.avo-kit-tests.\(name.filter(\.isLetter)).\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        return (HazeAppearanceSetting(store: store, key: "AvoAppearance", changed: Notification.Name("\(suite).changed")), store, suite)
    }

    @Test("System follows the Mac; Light and Dark are AppKit's own")
    func appearances() {
        #expect(HazeAppearance.system.nsAppearance == nil)
        #expect(HazeAppearance.light.nsAppearance?.name == .aqua)
        #expect(HazeAppearance.dark.nsAppearance?.name == .darkAqua)
        #expect(NSAppearance(named: .darkAqua)!.isHazeDark)
        #expect(NSAppearance(named: .accessibilityHighContrastDarkAqua)!.isHazeDark)
        #expect(!NSAppearance(named: .aqua)!.isHazeDark)
        #expect(!NSAppearance(named: .vibrantLight)!.isHazeDark)
    }

    @Test("The choice is kept as its raw value, System as none, an unknown one read as System")
    func storage() {
        let (setting, store, suite) = setting()
        defer { store.removePersistentDomain(forName: suite) }
        #expect(setting.appearance == .system)
        setting.set(.light)
        #expect(store.string(forKey: "AvoAppearance") == "light")
        #expect(setting.appearance == .light)
        setting.set(.dark)
        #expect(setting.appearance == .dark)
        setting.set(.system)
        #expect(store.object(forKey: "AvoAppearance") == nil)
        store.set("sepia", forKey: "AvoAppearance")
        #expect(setting.appearance == .system)
    }

    @Test("A follower applies the choice at once, and each change once")
    func follower() async {
        let (setting, store, suite) = setting()
        defer { store.removePersistentDomain(forName: suite) }
        setting.set(.dark)
        var applied: [HazeAppearance] = []
        let follower = setting.follow { applied.append($0) }
        #expect(applied == [.dark])
        setting.set(.light)
        // The distributed notification comes back through the run loop.
        for _ in 0..<50 where applied.count < 2 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(applied == [.dark, .light])
        #expect(follower.appearance == .light)
        setting.set(.light)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(applied == [.dark, .light])
    }

    @Test("The colours take the look of the appearance they are drawn in")
    func colours() {
        func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> UInt32 {
            var rgb: UInt32 = 0
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let c = color.usingColorSpace(.sRGB)!
                rgb = UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8
                    | UInt32((c.blueComponent * 255).rounded())
            }
            return rgb
        }
        let text = QuickHaze.nsRGB(0xF3F1E8, light: 0x1A2213)
        #expect(resolved(text, .darkAqua) == 0xF3F1E8)
        #expect(resolved(text, .aqua) == 0x1A2213)
        #expect(resolved(text, .accessibilityHighContrastDarkAqua) == 0xF3F1E8)
    }
}
