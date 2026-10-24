import AppKit
import AvoHazeUI
import AvoKeymap
import Foundation
import Testing
@testable import AvoKeymapUI

// A click zone comes back around its button after a screen edge held it:
// in a later editing too, and for a duplicated mode's twin.

private func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .avoSharedKit) }

@MainActor
@Suite("A click zone's place beside its button")
struct KeymapEditorZoneOffsetTests {
    @Test("A zone an earlier editing left held at the screen's edge comes back around its button")
    func aZoneHeldInAnEarlierEditingComesBack() {
        let held = Control(id: "t", kind: .tap(NormalizedPoint(1, 0.5)), triggers: [.key(.t)],
                           clickZone: ClickZone(area: NormalizedRect(0.9, 0.4, 1, 0.6), shape: .rectangle))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [held]))
        defer { editor.close() }
        editor.drag(from: (1, 0.5), to: (0.5, 0.5))
        let zone = editor.profile.controls[0].clickZone?.area
        #expect(near(zone?.center.x, 0.5), "\(String(describing: zone))")
    }

    @Test("A zone put beside its button at the edge keeps its place beside it")
    func aZoneBesideItsButtonKeepsItsOffset() {
        let beside = Control(id: "t", kind: .tap(NormalizedPoint(0.9, 0.5)), triggers: [.key(.t)],
                             clickZone: ClickZone(area: NormalizedRect(0.95, 0.4, 1, 0.6), shape: .rectangle))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [beside]))
        defer { editor.close() }
        editor.drag(from: (0.9, 0.5), to: (0.5, 0.5))
        #expect(near(editor.profile.controls[0].clickZone?.area.center.x, 0.575))
    }

    @Test("A duplicated mode's twin keeps its zone as far from its button as the original's")
    func aTwinKeepsItsZonesOffset() throws {
        let tap = Control(id: "t", kind: .tap(NormalizedPoint(0.5, 0.5)), triggers: [.key(.t)], modes: ["a"],
                          clickZone: ClickZone(area: NormalizedRect(0.47, 0.4, 0.57, 0.6), shape: .rectangle))
        let editor = Editor(KeymapProfile(package: "x", name: "x", controls: [tap], modes: [KeymapMode(id: "a", name: "A")]))
        defer { editor.close() }
        // Pushed against the right edge, then the mode duplicated.
        editor.drag(from: (0.5, 0.5), to: (1, 0.5))
        let duplicate = try #require(editor.item(L("Duplicate"), in: editor.model.modeMenu("a")))
        duplicate.action()
        let twin = try #require(editor.profile.controls.first { $0.id != "t" })
        #expect(twin.modes != ["a"])
        // The twin back in the middle: its zone where the original's was beside it.
        editor.drag(from: (1, 0.5), to: (0.5, 0.5))
        let moved = try #require(editor.profile.controls.first { $0.id == twin.id })
        #expect(moved.kind == .tap(NormalizedPoint(0.5, 0.5)))
        #expect(near(moved.clickZone?.area.center.x, 0.52), "\(String(describing: moved.clickZone?.area))")
    }
}
