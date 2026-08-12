import Testing
import Foundation
@testable import Pium

@MainActor
private final class StubUpdates: UpdateAvailability {
    var pendingUpdate: PendingUpdate?
    var automaticallyChecks = true
    var lastCheck: Date?
    private(set) var checked = 0
    private(set) var installed = 0

    init(pending: PendingUpdate? = nil) { pendingUpdate = pending }

    func checkForUpdates() { checked += 1 }
    func installPendingUpdate() { installed += 1; pendingUpdate = nil }
    func dismissPendingUpdate() { pendingUpdate = nil }
}

@MainActor
@Suite("Update notice")
struct UpdateNoticeTests {
    @Test func theNoticeIsAbsentWithNothingPending() {
        let state = LauncherState(updates: StubUpdates())
        #expect(state.pendingUpdate == nil)
    }

    @Test func theNoticeCarriesTheVersionOnOpen() {
        let updates = StubUpdates(pending: PendingUpdate(version: "0.2.0", build: "2"))
        let state = LauncherState(updates: updates)

        #expect(state.pendingUpdate?.version == "0.2.0")
    }

    @Test func activatingTheNoticeAsksForTheInstall() {
        let updates = StubUpdates(pending: PendingUpdate(version: "0.2.0", build: "2"))
        let state = LauncherState(updates: updates)

        state.installPendingUpdate()

        #expect(updates.installed == 1)
        #expect(state.pendingUpdate == nil)
    }

    @Test func dismissingLeavesTheUpdateFoundButUnshown() {
        let updates = StubUpdates(pending: PendingUpdate(version: "0.2.0", build: "2"))
        let state = LauncherState(updates: updates)

        state.dismissPendingUpdate()

        #expect(state.pendingUpdate == nil)
        #expect(updates.installed == 0)
    }
}
