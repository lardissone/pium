import AppKit
import OSLog

/// Owns Pium's controllers and wires them to each other.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "Lifecycle")

    private let hotkeyController = GlobalHotkeyController()
    private let applicationIndex: ApplicationIndex
    private let panelController: LauncherPanelController
    private let onboardingController = OnboardingWindowController()
    private let settingsController = SettingsWindowController()
    private var menuBarController: MenuBarController?

    /// The panel is built here rather than lazily so the first press of the
    /// shortcut does not pay for constructing its `NSHostingView`, which would
    /// come straight out of the 100 ms budget for showing the launcher.
    override init() {
        let index = ApplicationIndex()
        applicationIndex = index
        panelController = LauncherPanelController(
            coordinator: SearchCoordinator(providers: [
                ApplicationProvider(index: index)
            ])
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            onOpenLauncher: { [weak self] in self?.panelController.show() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        applicationIndex.refresh()
        applicationIndex.startObserving()

        registerShortcut(Preferences.shared.shortcut)

        if !Preferences.shared.hasCompletedOnboarding {
            onboardingController.present(shortcut: Preferences.shared.shortcut) {
                Preferences.shared.hasCompletedOnboarding = true
            }
        }
    }

    /// Re-registers the global hotkey. Called at launch and whenever the user
    /// records a new combination in Settings.
    func registerShortcut(_ shortcut: HotkeyShortcut) {
        do {
            try hotkeyController.register(shortcut) { [weak self] in
                self?.panelController.toggle()
            }
        } catch {
            // A conflict is a normal, recoverable condition: another app owns
            // the combination. Pium stays usable through the menubar.
            //
            // Surfacing this in Settings is Phase 6 work, with the other error
            // states.
            logger.error(
                "Could not register \(shortcut.displayString, privacy: .public): \(error)"
            )
        }
    }

    private func openSettings() {
        settingsController.present { [weak self] shortcut in
            self?.registerShortcut(shortcut)
        }
    }
}
