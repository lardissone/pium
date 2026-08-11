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
    private static let frameAutosaveName = "settings"

    private var window: NSWindow?

    func present(
        frecency: any FrecencyStoring,
        access: ProtectedFolderAccess,
        onShortcutChanged: @escaping (HotkeyShortcut) -> Void,
        pluginIndex: PluginIndex,
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring
    ) {
        // Reuse the existing window so the menu item raises Settings rather
        // than stacking a second copy.
        if let window {
            raise(window)
            return
        }

        // Sized explicitly rather than from the hosting controller's fitting
        // size: a grouped `Form` reports no useful height when hosted in
        // AppKit, and the window collapses to an empty strip. The Plugins
        // tab's master–detail list does not fit in the 260-point height the
        // other tabs were happy with.
        //
        // Resizable because the content is the user's: a plugin's name, its
        // declared command, and its environment variables are all as long as
        // its author made them, and a fixed width clips them with no way out.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "settings.windowTitle")
        window.isReleasedWhenClosed = false
        // Pium has no Dock icon and does not appear in the application
        // switcher, so a window that slips behind another one cannot be
        // brought back the ways a person would try. Floating keeps it in
        // reach, and closing it is the way it goes away — the same reasoning
        // `OnboardingWindowController` already applies to first launch.
        window.level = .floating
        window.contentMinSize = NSSize(width: 560, height: 360)
        window.contentView = NSHostingView(
            rootView: SettingsView(
                frecency: frecency,
                access: access,
                onShortcutChanged: onShortcutChanged,
                pluginIndex: pluginIndex,
                configuration: configuration,
                secrets: secrets
            )
        )
        // Whatever size the user settles on is the size they get next time;
        // a first run has nothing saved and lands in the middle instead.
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }

        self.window = window
        raise(window)
    }

    /// Brings the window to the front and gives it the keyboard.
    ///
    /// `orderFrontRegardless` as well as activating: an accessory app is not
    /// always granted the front on asking, and `makeKeyAndOrderFront` obeys
    /// that refusal — which is how choosing Settings from the menubar could
    /// leave the window opening behind whatever the person was looking at,
    /// with no icon in the Dock or the switcher to reach it by.
    private func raise(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
