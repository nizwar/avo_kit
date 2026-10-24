import AppKit
import AvoKeymap
import AvoKitResources
import Foundation
import Testing
@testable import AvoKeymapUI

// The editor's words: one control is not "1 controls", and a mode is
// worked in, not acted in.

@MainActor
@Suite("The key mapping editor's wording")
struct KeymapEditorWordingTests {
    private var english: Bundle? {
        Bundle.avoSharedKit.url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))
    }

    @Test("Counts say one control and two controls")
    func countsArePlural() throws {
        let en = try #require(english)
        #expect(String(localized: "\(1) controls that work only there or switch to it go too. Cancel in the editor still undoes it.", bundle: en)
            == "One control that works only there or switches to it goes too. Cancel in the editor still undoes it.")
        #expect(String(localized: "\(2) controls that work only there or switch to it go too. Cancel in the editor still undoes it.", bundle: en)
            == "2 controls that work only there or switch to it go too. Cancel in the editor still undoes it.")
        let kind = "FPS"
        #expect(String(localized: "The controller is laid out as in \(kind) games: \(1) controls. Cancel undoes it.", bundle: en)
            == "The controller is laid out as in FPS games: 1 control. Cancel undoes it.")
        #expect(String(localized: "The controller is laid out as in \(kind) games: \(3) controls. Cancel undoes it.", bundle: en)
            == "The controller is laid out as in FPS games: 3 controls. Cancel undoes it.")
        #expect(String(localized: "Still without a key: \(1), because your controls already use theirs. Select each “?” and press a key.", bundle: en)
            .hasPrefix("Still without a key: one,"))
    }

    @Test("A control works in its modes")
    func worksIn() {
        let tap = Control(id: "tap", kind: .tap(NormalizedPoint(0.1, 0.1)), triggers: [.key(.t)])
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap],
                                          modes: [KeymapMode(id: "a", name: "On foot"), KeymapMode(id: "b", name: "Car")]))
        defer { editor.close() }
        editor.model.select("tap")
        editor.model.setActsIn(["a", "b"])
        let name = String(localized: "Tap", bundle: .avoSharedKit)
        #expect(editor.model.status == String(localized: "“\(name)” works in \(["On foot", "Car"].formatted(.list(type: .and))).", bundle: .avoSharedKit))
        #expect(String(localized: "Click a button in the game, then press its key.", bundle: .avoSharedKit) != "")
    }
}
