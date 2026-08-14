import Testing
import Foundation
@testable import Pium

/// The controller is tested through the protocol and through the one decision
/// that is Pium's rather than Sparkle's: whether a relaunch may proceed.
@MainActor
@Suite("Update controller")
struct UpdateControllerTests {
    /// PIUM-134: the guard is right and invisible. Holding the relaunch is
    /// exactly what PRD §13 asks for, but the person pressed Install and
    /// Relaunch and watched nothing happen — which is what a broken button
    /// also looks like.
    @Test func postponingARelaunchSaysSo() {
        var announced = 0
        let controller = UpdateController(isBusy: { true }, announceWait: { announced += 1 })

        _ = controller.postponeRelaunch {}

        #expect(announced == 1)
    }

    /// And says nothing when there was nothing to wait for, or every ordinary
    /// update would explain itself for no reason.
    @Test func aRelaunchThatIsNotHeldBackSaysNothing() {
        var announced = 0
        let controller = UpdateController(isBusy: { false }, announceWait: { announced += 1 })

        _ = controller.postponeRelaunch {}

        #expect(announced == 0)
    }

    @Test func aFoundUpdateIsHeldRatherThanInstalled() {
        let controller = UpdateController(isBusy: { false })
        #expect(controller.pendingUpdate == nil)

        controller.noteUpdateFound(PendingUpdate(version: "0.2.0"))

        // PRD §13: found is not downloaded, and not installed.
        #expect(controller.pendingUpdate == PendingUpdate(version: "0.2.0"))
    }

    /// PRD §13: an update must not interrupt an active command.
    @Test func aRelaunchWaitsWhileACommandRuns() {
        var busy = true
        let controller = UpdateController(isBusy: { busy })
        var relaunched = false

        let postponed = controller.postponeRelaunch { relaunched = true }

        #expect(postponed == true)
        #expect(relaunched == false)

        busy = false
        controller.commandFinished()

        #expect(relaunched == true)
    }

    /// A run ending is not proof the slot is free — another command can claim
    /// it in the same breath. The relaunch stays armed until it really is.
    @Test func aRelaunchStaysArmedWhileTheSlotIsClaimedAgain() {
        var busy = true
        let controller = UpdateController(isBusy: { busy })
        var relaunched = false
        _ = controller.postponeRelaunch { relaunched = true }

        controller.commandFinished()

        #expect(relaunched == false)

        busy = false
        controller.commandFinished()

        #expect(relaunched == true)
    }

    /// Runs keep ending after the one that was holding the relaunch. Only the
    /// first of them may resume it.
    @Test func aResumedRelaunchDoesNotFireTwice() {
        var busy = true
        let controller = UpdateController(isBusy: { busy })
        var relaunches = 0
        _ = controller.postponeRelaunch { relaunches += 1 }

        busy = false
        controller.commandFinished()
        controller.commandFinished()

        #expect(relaunches == 1)
    }

    /// Installing is Sparkle's job. All Pium does is stand out of the way of
    /// the window it is about to open.
    @Test func installingClearsTheNotice() {
        let controller = UpdateController(isBusy: { false })
        controller.noteUpdateFound(PendingUpdate(version: "0.2.0"))

        controller.installPendingUpdate()

        #expect(controller.pendingUpdate == nil)
    }

    @Test func aRelaunchWithNothingRunningProceedsImmediately() {
        let controller = UpdateController(isBusy: { false })
        var relaunched = false

        let postponed = controller.postponeRelaunch { relaunched = true }

        #expect(postponed == false)
        #expect(relaunched == false)  // Sparkle relaunches; Pium does not.
    }
}
