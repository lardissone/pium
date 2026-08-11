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
            outputMode: .toast,
            startedAt: Date(),
            state: .ended(.cancelled),
            standardOutput: "",
            standardError: "",
            wasTruncated: false
        )
    }

    /// The whole path a real run takes to the screen, with a real process at
    /// the far end: the manager keeps the mode the manifest declared on the
    /// run's own record, `HUDPresentation` reads it there, and the panel that
    /// results is placed inside a screen somebody can read it on.
    @Test func atoastRunPutsWhatItPrintedOnScreen() async throws {
        let manifest = PluginManifest(
            schemaVersion: 1,
            id: "demo.probe",
            name: "Probe",
            description: nil,
            keywords: [],
            aliases: [],
            icon: nil,
            input: PluginInput(mode: .none, placeholder: nil),
            command: PluginCommand(executable: "echo", arguments: ["hola"], workingDirectory: nil),
            configuration: [],
            output: PluginOutput(mode: .toast),
            timeoutSeconds: nil,
            confirmBeforeRun: nil
        )
        // Long enough that the running HUD never appears: this is about what a
        // *finished* run leaves behind.
        let controller = HUDController(runningDelay: .seconds(60))
        let manager = ExecutionManager(
            configuration: PluginConfigurationStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!
            ),
            secrets: InMemorySecretStore(secrets: [:]),
            searchPaths: ["/usr/bin", "/bin"],
            onFinished: { record in
                controller.finishRunning(id: record.id, with: HUDPresentation.forOutcome(record))
            }
        )

        _ = try manager.run(
            PluginRecord(
                fileURL: URL(filePath: "/tmp/probe.pium.json"), manifest: manifest, diagnostic: nil
            ),
            input: ""
        ).get()

        let deadline = ContinuousClock.now + .seconds(10)
        while controller.visibleCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.visibleCount == 1, "A toast run that printed must leave a HUD")

        let frame = try #require(controller.frames.first)
        let visible = try #require(NSScreen.main ?? NSScreen.screens.first).visibleFrame
        #expect(visible.contains(frame), "The HUD is off the screen it was placed on: \(frame)")
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
        let outcome = HUDPresentation.forOutcome(cancelledRecord(id: id))
        controller.finishRunning(id: id, with: outcome)
        #expect(controller.visibleCount == 0)
    }
}
