import Foundation
import Sparkle

/// Sparkle, and the two decisions around it that belong to Pium.
///
/// The first is when a found update is shown: PRD §13 wants a discreet notice
/// the next time the launcher opens, not a window in front of whatever the
/// user was doing. Sparkle's *gentle reminders* are exactly that contract —
/// `standardUserDriverShouldHandleShowingScheduledUpdate` returning `false`
/// hands a scheduled update back to us, while a check the user asked for
/// keeps Sparkle's own UI, which is correct: they are looking at it.
///
/// The second is the relaunch. A plugin's command survives the launcher
/// closing; it must also survive an update deciding it is time to quit.
@MainActor
@Observable
final class UpdateController: NSObject, UpdateAvailability {
    private(set) var pendingUpdate: PendingUpdate?

    /// Held so a postponed relaunch can be resumed when the run ends.
    @ObservationIgnored private var resumeRelaunch: (() -> Void)?
    @ObservationIgnored private let isBusy: () -> Bool
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    /// `isBusy` is a closure rather than a reference to `ExecutionManager` so
    /// the guard can be tested without building an execution stack.
    init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        super.init()
    }

    /// Separate from `init` because a test wants the decisions without the
    /// framework, and because starting the updater begins network activity.
    func start() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller?.updater.updateCheckInterval = 21600
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// The notice was activated: hand it back to Sparkle, which owns
    /// downloading, verifying, and installing. Clearing the notice first
    /// means Sparkle's own window is not shadowed by Pium's row.
    func installPendingUpdate() {
        pendingUpdate = nil
        controller?.updater.checkForUpdates()
    }

    func dismissPendingUpdate() {
        pendingUpdate = nil
    }

    // MARK: - The decisions, separated from Sparkle so they can be tested

    func noteUpdateFound(_ update: PendingUpdate) {
        pendingUpdate = update
    }

    /// `true` if the relaunch must wait. The handler is kept and invoked by
    /// `commandFinished()`.
    func postponeRelaunch(_ resume: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        resumeRelaunch = resume
        return true
    }

    /// Called when the run slot empties. Resumes a relaunch that was waiting
    /// on it, and does nothing otherwise.
    func commandFinished() {
        guard let resume = resumeRelaunch else { return }
        resumeRelaunch = nil
        resume()
    }
}

// MARK: - Sparkle

/// Sparkle declares `SPUUpdaterDelegate` as main-actor isolated, so these
/// members are ordinary main-actor methods.
extension UpdateController: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        postponeRelaunch(installHandler)
    }
}

/// Unlike `SPUUpdaterDelegate`, this protocol carries no isolation, so its
/// members have to be `nonisolated` to satisfy it. The standard user driver
/// calls them on the main thread — `assumeIsolated` states that as a checked
/// assertion rather than hopping and losing the return values these need.
extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Let Sparkle take anything it would put in immediate focus; Pium
        // shows everything else in the launcher.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Sparkle is showing it — a user-initiated check. Nothing to add.
        guard !handleShowingUpdate else { return }

        MainActor.assumeIsolated {
            noteUpdateFound(
                PendingUpdate(
                    version: update.displayVersionString,
                    build: update.versionString
                )
            )
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { pendingUpdate = nil }
    }
}
