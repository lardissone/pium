import Testing
import AppKit
import Foundation
@testable import Pium

@Suite("HUD controller")
@MainActor
struct HUDControllerTests {
    /// Short enough to keep these tests fast; the production default lives in
    /// `HUDController.init`, not here.
    private static let runningDelay: Duration = .milliseconds(200)

    private func presentation(_ body: String, duration: Duration) -> HUDPresentation {
        HUDPresentation(kind: .success, title: "Probe", body: body, duration: duration)
    }

    private func running(_ pluginName: String = "Probe") -> RunningPresentation {
        RunningPresentation(pluginName: pluginName, startedAt: Date())
    }

    private func cancelledRecord(id: UUID) -> ExecutionRecord {
        ExecutionRecord(
            id: id,
            pluginID: "demo.probe",
            pluginName: "Probe",
            startedAt: Date(),
            state: .cancelled,
            standardOutput: "",
            standardError: "",
            wasTruncated: false
        )
    }

    @Test func showingOneMakesOnePanel() {
        let controller = HUDController()
        controller.show(presentation("done", duration: .seconds(60)))
        #expect(controller.visibleCount == 1)
    }

    /// Three results in a row leave three panels — the reason they stack
    /// rather than replace each other.
    @Test func theystack() {
        let controller = HUDController()
        for index in 0..<3 {
            controller.show(presentation("\(index)", duration: .seconds(60)))
        }
        #expect(controller.visibleCount == 3)
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
    }

    /// Most plugins run and finish well inside the delay — the reason it
    /// exists at all — so nothing should ever have appeared for the caller to
    /// have shown or torn down.
    @Test func arunThatEndsBeforeTheThresholdShowsNoRunningHUDAtAll() async throws {
        let controller = HUDController(runningDelay: Self.runningDelay)
        let id = UUID()
        controller.showRunning(id: id, presentation: running(), onCancel: {})
        try await Task.sleep(for: .milliseconds(50))
        controller.finishRunning(id: id, with: nil)
        // Outlives the original delay so a late-firing pending task, if the
        // cancellation above failed to stop it, would have shown by now.
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.visibleCount == 0)
    }

    @Test func arunThatOutlivesTheThresholdShowsOneAndItIsGoneOnceTheRunEnds() async throws {
        let controller = HUDController(runningDelay: Self.runningDelay)
        let id = UUID()
        controller.showRunning(id: id, presentation: running(), onCancel: {})
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.visibleCount == 1)
        controller.finishRunning(id: id, with: nil)
        #expect(controller.visibleCount == 0)
    }

    @Test func theOutcomeHUDReplacesTheRunningOneRatherThanStackingBeneathIt() async throws {
        let controller = HUDController(runningDelay: Self.runningDelay)
        let id = UUID()
        controller.showRunning(id: id, presentation: running(), onCancel: {})
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.visibleCount == 1)
        controller.finishRunning(id: id, with: presentation("done", duration: .seconds(60)))
        #expect(controller.visibleCount == 1)
    }

    /// Exercises the real `HUDPresentation.forOutcome` path for a cancelled
    /// run, not a bare `nil`: PRD policy is that a cancelled run shows
    /// nothing, and this is what actually produces that `nil` in the app.
    @Test func acancelledRunLeavesNothingOnScreen() async throws {
        let controller = HUDController(runningDelay: Self.runningDelay)
        let id = UUID()
        controller.showRunning(id: id, presentation: running(), onCancel: {})
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.visibleCount == 1)
        let outcome = HUDPresentation.forOutcome(cancelledRecord(id: id), mode: .toast)
        controller.finishRunning(id: id, with: outcome)
        #expect(controller.visibleCount == 0)
    }
}
