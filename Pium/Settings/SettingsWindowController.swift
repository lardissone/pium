import AppKit
import SwiftUI

/// Hosts Settings in a normal window that Pium owns.
///
/// SwiftUI's `Settings` scene is opened through a private selector
/// (`showSettingsWindow:`) that relies on a responder being present to handle
/// it. An accessory app with no windows open has no such responder, so the menu
/// item silently did nothing. Owning the window removes that dependency.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func present(
        frecency: any FrecencyStoring,
        onShortcutChanged: @escaping (HotkeyShortcut) -> Void,
        pluginIndex: PluginIndex,
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring
    ) {
        // Reuse the existing window so the menu item raises Settings rather
        // than stacking a second copy.
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Sized explicitly rather than from the hosting controller's fitting
        // size: a grouped `Form` reports no useful height when hosted in
        // AppKit, and the window collapses to an empty strip. The Plugins
        // tab's master–detail list does not fit in the 260-point height the
        // other tabs were happy with.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "settings.windowTitle")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(
                frecency: frecency,
                onShortcutChanged: onShortcutChanged,
                pluginIndex: pluginIndex,
                configuration: configuration,
                secrets: secrets
            )
        )
        window.center()

        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
