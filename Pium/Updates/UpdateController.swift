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
    ///
    /// A second updater would run a scheduled-check timer of its own against
    /// the same bundle, so starting twice is ignored rather than replacing
    /// the first.
    ///
    /// The check interval is not set here. Sparkle's setter writes to user
    /// defaults, which outrank `Info.plist` — an interval set in code would
    /// stick to the machine and quietly overrule every later build. It lives
    /// in `Info.plist` as `SUScheduledCheckInterval`, with the rest of the
    /// Sparkle configuration.
    func start() {
        guard controller == nil else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Before `start()` there is no updater to ask, so this reads and writes
    /// the same key in the same order Sparkle's own `SUHost` does — user
    /// defaults, then the bundle. A Settings toggle bound to this must not
    /// report a value nobody chose, or discard one the user did.
    var automaticallyChecks: Bool {
        get {
            guard let updater = controller?.updater else {
                return UserDefaults.standard.object(forKey: Self.automaticChecksKey) as? Bool
                    ?? Bundle.main.object(forInfoDictionaryKey: Self.automaticChecksKey) as? Bool
                    ?? false
            }
            return updater.automaticallyChecksForUpdates
        }
        set {
            guard let updater = controller?.updater else {
                UserDefaults.standard.set(newValue, forKey: Self.automaticChecksKey)
                return
            }
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    private static let automaticChecksKey = "SUEnableAutomaticChecks"

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
    ///
    /// Busy-ness is checked again rather than inferred from being called: if
    /// another command has claimed the slot by now, the relaunch stays armed
    /// for the next time it empties. That keeps "an update never interrupts a
    /// command" true here rather than in whoever calls this.
    func commandFinished() {
        guard !isBusy(), let resume = resumeRelaunch else { return }
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
        // Never Sparkle's window, whatever it thinks of the moment. Pium has
        // no window the user is already looking at, so Sparkle showing this
        // one means activating a menubar app over whatever they were doing
        // instead. A check the user asked for does not come through here.
        false
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
