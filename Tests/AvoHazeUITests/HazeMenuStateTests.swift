import AppKit
@testable import AvoHazeUI
import Testing

/// A haze menu's rows chosen: most close the menu and then act; one that keeps it open (Volume Up) acts at once.
@MainActor
struct HazeMenuStateTests {
    @Test func anItemThatKeepsTheMenuOpenActsEachTimeAndTheMenuStays() async throws {
        var presses = 0
        var closed = false
        let louder = HazeMenuItem(title: "Volume Up", keepsMenuOpen: true) { presses += 1 }
        let state = HazeMenuState(entries: [.item(louder)])
        state.onClose = { _ in closed = true }
        state.choose(louder)
        state.choose(louder)
        #expect(presses == 2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!closed)

        var opened = 0
        let open = HazeMenuItem(title: "Open") { opened += 1 }
        let other = HazeMenuState(entries: [.item(open)])
        other.onClose = { _ in closed = true }
        other.choose(open)
        try await Task.sleep(for: .milliseconds(200))
        #expect(opened == 1 && closed)
    }
}
