import AppKit
@testable import AvoKeymapUI
import Testing

/// Key Visibility fades the keys on the game as a whole, letters with their
/// plates, down to 5%.
@MainActor
@Suite(.serialized)
struct KeymapHintsVisibilityTests {
    @Test("The steps go down to 5% and 10%, and the slider as far")
    func faintSteps() {
        let steps = KeymapHints.steps.map(\.opacity)
        #expect(steps == [0.05, 0.1, 0.25, 0.5, 0.75, 1])
        #expect(KeymapHints.opacityRange.lowerBound == 0.05)
    }

    @Test("The keys' layer takes the visibility, letters and all")
    func theLayerFades() {
        let saved = UserDefaults.standard.object(forKey: "AvoKeymapHintsOpacity")
        defer { UserDefaults.standard.set(saved, forKey: "AvoKeymapHintsOpacity") }
        let view = KeymapHintsView(displayRect: { CGRect(x: 0, y: 0, width: 400, height: 200) })
        KeymapHints.opacity = 0.05
        #expect(abs(view.alphaValue - 0.05) < 0.001)
        KeymapHints.opacity = 0.1
        #expect(abs(view.alphaValue - 0.1) < 0.001)
        // Below the range it stays at its least.
        KeymapHints.opacity = 0.01
        #expect(abs(view.alphaValue - 0.05) < 0.001)
    }
}
