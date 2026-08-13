import AppKit

/// Pium's menubar item and its menu.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onOpenLauncher: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenPluginsFolder: () -> Void
    private let onReloadPlugins: () -> Void
    private let onCancel: () -> Void
    private let onOpenAbout: () -> Void
    private let onCheckForUpdates: () -> Void
    /// The plugin holding the run slot, by name, or `nil` while nothing runs.
    private var activePlugin: String?

    /// Exposed for tests: the menu's shape — its items, their identifiers and
    /// titles — is testable. Its pixels are not.
    var menu: NSMenu { statusItem.menu ?? NSMenu() }

    init(
        onOpenLauncher: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenPluginsFolder: @escaping () -> Void,
        onReloadPlugins: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.onOpenLauncher = onOpenLauncher
        self.onOpenSettings = onOpenSettings
        self.onOpenPluginsFolder = onOpenPluginsFolder
        self.onReloadPlugins = onReloadPlugins
        self.onCancel = onCancel
        self.onOpenAbout = onOpenAbout
        self.onCheckForUpdates = onCheckForUpdates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setActive(nil)
    }

    deinit {
        // `deinit` is not statically main-actor-isolated, but every instance
        // is created, held, and released on the main actor — by `AppDelegate`
        // for the app's whole lifetime, and by a test function for the length
        // of one test — so it is always actually safe to touch `statusItem`
        // here. Without this, each test that builds a controller leaves a
        // real status item behind in the menu bar.
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    /// A run in progress, by name, or `nil`. Changing it rebuilds the menu:
    /// the Cancel entry exists only while there is something to cancel, so it
    /// can name what it would stop. The status item's symbol changes too —
    /// PRD §11's "subtle activity" — without animating, which would cost idle
    /// CPU for as long as the run does.
    func setActive(_ plugin: String?) {
        activePlugin = plugin
        statusItem.button?.image = NSImage(
            systemSymbolName: plugin == nil ? "sparkle" : "hourglass",
            accessibilityDescription: String(localized: "menubar.accessibilityLabel")
        )
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(
            title: String(localized: "menubar.openPium"),
            action: #selector(openLauncher)
        ))
        if let activePlugin {
            let cancelItem = menuItem(
                title: String(localized: "menubar.cancel \(activePlugin)"),
                action: #selector(cancelRun)
            )
            cancelItem.identifier = NSUserInterfaceItemIdentifier("cancel")
            menu.addItem(cancelItem)
        }
        let updatesItem = menuItem(
            title: String(localized: "menubar.checkForUpdates"),
            action: #selector(checkForUpdates)
        )
        updatesItem.identifier = NSUserInterfaceItemIdentifier("checkForUpdates")
        menu.addItem(updatesItem)
        menu.addItem(menuItem(
            title: String(localized: "menubar.settings"),
            action: #selector(openSettings)
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: String(localized: "menubar.openPluginsFolder"),
            action: #selector(openPluginsFolder)
        ))
        menu.addItem(menuItem(
            title: String(localized: "menubar.reloadPlugins"),
            action: #selector(reloadPlugins)
        ))
        menu.addItem(.separator())
        // `LSUIElement` means there is no application menu to carry About, so
        // this menu is the only place it can live. PRD §6.1 does not list it;
        // it is an addition, not a reading of that section.
        let aboutItem = menuItem(
            title: String(localized: "menubar.about"),
            action: #selector(openAbout)
        )
        aboutItem.identifier = NSUserInterfaceItemIdentifier("about")
        menu.addItem(aboutItem)
        menu.addItem(menuItem(
            title: String(localized: "menubar.quit"),
            action: #selector(quit)
        ))
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openLauncher() {
        onOpenLauncher()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openPluginsFolder() {
        onOpenPluginsFolder()
    }

    @objc private func reloadPlugins() {
        onReloadPlugins()
    }

    @objc private func cancelRun() {
        onCancel()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
