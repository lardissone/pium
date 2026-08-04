import ServiceManagement
import OSLog

/// Opt-in launch at login, through the macOS service rather than a login-item
/// helper bundle.
///
/// `SMAppService` reads the app's own bundle, so it only behaves correctly for
/// a signed build in `/Applications`. A build running from DerivedData may
/// report `.requiresApproval` or fail outright; that is expected and is not a
/// defect in this file.
@MainActor
final class LoginItemController {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "LoginItem")

    /// Reads the live service status rather than a cached flag, so the Settings
    /// toggle cannot drift from what macOS actually does.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        logger.info("Launch at login set to \(enabled, privacy: .public)")
    }
}
