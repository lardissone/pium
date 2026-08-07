import AppKit
import OSLog

/// Owns Pium's controllers and wires them to each other.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "Lifecycle")

    private let hotkeyController = GlobalHotkeyController()
    private let applicationIndex: ApplicationIndex
    private let pluginIndex: PluginIndex
    private let pluginConfiguration = PluginConfigurationStore()
    private let pluginSecrets = KeychainSecretStore()
    private let executionManager: ExecutionManager
    /// Built once and shared: the coordinator reads it to rank, the panel writes
    /// to it on selection, and Settings erases it.
    private let frecency: FrecencyStore
    private let panelController: LauncherPanelController
    /// Outlives the launcher panel by design (PRD §11): a HUD it is showing
    /// must not close just because the panel that started it did.
    private let hudController: HUDController
    private let onboardingController = OnboardingWindowController()
    private let settingsController = SettingsWindowController()
    private var menuBarController: MenuBarController?

    /// The panel is built here rather than lazily so the first press of the
    /// shortcut does not pay for constructing its `NSHostingView`, which would
    /// come straight out of the 100 ms budget for showing the launcher.
    override init() {
        let index = ApplicationIndex()
        applicationIndex = index
        let plugins = PluginIndex()
        pluginIndex = plugins
        let frecency = FrecencyStore()
        self.frecency = frecency
        let configuration = pluginConfiguration
        let secrets = pluginSecrets
        let hud = HUDController()
        hudController = hud
        let executions = ExecutionManager(
            configuration: configuration,
            secrets: secrets,
            onFinished: { record, mode in
                guard let presentation = HUDPresentation.forOutcome(record, mode: mode) else {
                    return
                }
                hud.show(presentation)
            }
        )
        executionManager = executions
        panelController = LauncherPanelController(
            coordinator: SearchCoordinator(
                providers: [
                    // Listed in the PRD's tie-break order. Ranking does not read
                    // this order, but a reader looking for it should find it.
                    PluginProvider(
                        index: plugins,
                        status: {
                            PluginStatusResolver(
                                configuration: configuration,
                                secrets: secrets,
                                disabledIDs: Preferences.shared.disabledPluginIDs
                            )
                        },
                        execute: { record, input in
                            if case .failure(let failure) = executions.run(record, input: input) {
                                // A refusal here means nothing ever ran, so
                                // there is no `ExecutionRecord` for a HUD to
                                // show — the log is the only place it lands.
                                Logger(subsystem: Signposts.subsystem, category: "Execution")
                                    .error("\(failure.message, privacy: .public)")
                            }
                        }
                    ),
                    ApplicationProvider(index: index),
                    SpotlightFileProvider(),
                ],
                frecency: frecency
            ),
            frecency: frecency
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            onOpenLauncher: { [weak self] in self?.panelController.show() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenPluginsFolder: {
                NSWorkspace.shared.activateFileViewerSelecting([PluginLoader.defaultRoot])
            },
            onReloadPlugins: { [weak self] in self?.pluginIndex.refresh() }
        )

        // Done here rather than in `PiumApp`: the menu exists only once the app
        // has finished launching, and it is `AppDelegate` that owns the window
        // the item has to reach.
        if let menu = NSApp.mainMenu {
            let rewired = SettingsMenuItem.retarget(
                in: menu, to: self, action: #selector(openSettingsFromMenu)
            )
            if !rewired {
                logger.error("No ⌘, item in the main menu; Settings is reachable from the menubar")
            }
        }

        applicationIndex.refresh()
        applicationIndex.startObserving()

        // Created at launch so "Open Plugins Folder" always has somewhere to go,
        // and onboarding's promise that the folder exists is kept.
        PluginLoader.createRootIfNeeded()
        pluginIndex.refresh()
        pluginIndex.startObserving()

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

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    private func openSettings() {
        settingsController.present(
            frecency: frecency,
            onShortcutChanged: { [weak self] shortcut in
                self?.registerShortcut(shortcut)
            },
            pluginIndex: pluginIndex,
            configuration: pluginConfiguration,
            secrets: pluginSecrets
        )
    }
}
