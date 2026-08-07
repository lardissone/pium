import Testing
import AppKit
@testable import Pium

@Suite("HUD controller")
@MainActor
struct HUDControllerTests {
    private func presentation(_ body: String, duration: Duration) -> HUDPresentation {
        HUDPresentation(kind: .success, title: "Probe", body: body, duration: duration)
    }

    @Test func showingOneMakesOnePanel() {
        let controller = HUDController()
        controller.show(presentation("done", duration: .seconds(60)))
        #expect(controller.visibleCount == 1)
        controller.dismissAll()
    }

    /// Three results in a row leave three panels — the reason they stack
    /// rather than replace each other.
    @Test func theystack() {
        let controller = HUDController()
        for index in 0..<3 {
            controller.show(presentation("\(index)", duration: .seconds(60)))
        }
        #expect(controller.visibleCount == 3)
        controller.dismissAll()
    }

    @Test func apanelGoesAwayWhenItsTimeIsUp() async throws {
        let controller = HUDController()
        controller.show(presentation("done", duration: .milliseconds(200)))
        #expect(controller.visibleCount == 1)
        try await Task.sleep(for: .milliseconds(700))
        #expect(controller.visibleCount == 0)
    }

    /// The panels behind close their gap, so a stack never grows holes.
    @Test func theonesBehindMoveUpWhenOneCloses() async throws {
        let controller = HUDController()
        controller.show(presentation("first", duration: .milliseconds(200)))
        controller.show(presentation("second", duration: .seconds(60)))
        let secondBefore = controller.frames.last
        try await Task.sleep(for: .milliseconds(700))
        #expect(controller.visibleCount == 1)
        #expect(controller.frames.first != secondBefore)
        controller.dismissAll()
    }
}
