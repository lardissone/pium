import AppKit

/// Pium's menubar item and its menu.
///
/// The PRD's plugin, reload, cancel, and update entries ship with the features
/// that make them meaningful, in Phases 4, 5, and 7.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onOpenLauncher: () -> Void
    private let onOpenSettings: () -> Void

    init(
        onOpenLauncher: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenLauncher = onOpenLauncher
        self.onOpenSettings = onOpenSettings
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
