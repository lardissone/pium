import Foundation

/// What the rest of Pium knows about updates.
///
/// One protocol so `LauncherState` and `UpdatesSettingsView` can be exercised
/// without a real updater, a network, or a signed feed.
@MainActor
protocol UpdateAvailability: AnyObject {
    /// A version found by a scheduled check and not yet acted on. PRD §13
    /// keeps discovery and installation separate, so this is a notice, not a
    /// download in progress.
    var pendingUpdate: PendingUpdate? { get }
    var automaticallyChecks: Bool { get set }
    var lastCheck: Date? { get }
    func checkForUpdates()
    func installPendingUpdate()
}
