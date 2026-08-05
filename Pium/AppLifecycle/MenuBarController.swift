import AppKit

/// Pium's menubar item and its menu.
///
/// The PRD's cancel and update entries ship with the features that make them
/// meaningful, in Phases 5 and 7.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onOpenLauncher: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenPluginsFolder: () -> Void
    private let onReloadPlugins: () -> Void

    init(
        onOpenLauncher: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenPluginsFolder: @escaping () -> Void,
        onReloadPlugins: @escaping () -> Void
    ) {
        self.onOpenLauncher = onOpenLauncher
        self.onOpenSettings = onOpenSettings
        self.onOpenPluginsFolder = onOpenPluginsFolder
        self.onReloadPlugins = onReloadPlugins
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkle",
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
