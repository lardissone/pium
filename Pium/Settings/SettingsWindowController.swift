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
    /// Not private so a test can clear the saved frame and exercise a first
    /// run, which is the only time the default size is what opens.
    static let frameAutosaveName = "settings"

    private var window: NSWindow?

    func present(
        frecency: any FrecencyStoring,
        access: ProtectedFolderAccess,
        onShortcutChanged: @escaping (HotkeyShortcut) -> Void,
        bookmarks: BookmarkStore,
        applications: ApplicationIndex,
        pluginIndex: PluginIndex,
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring,
        updates: any UpdateAvailability,
        onPreviewHUD: @escaping () -> Void
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
        //
        // The width carries the sidebar as well as the content. Settings was
        // 620 wide when its sections were tabs across the title bar; the
        // sidebar takes about 150 of its own, so the same room is left for a
        // section's own controls.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "settings.windowTitle")
        window.isReleasedWhenClosed = false
        // The sidebar runs the full height of the window, traffic lights over
        // it, the way every Mac app with a sidebar looks. Without this the
        // title bar is a solid strip across the top and the sidebar starts
        // underneath it, which reads as a panel bolted into a window rather
        // than as the window's own edge.
        //
        // The title is hidden rather than moved: the sidebar already says
        // which section is showing, and the window says which app it is by
        // being the only one Pium opens.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Pium has no Dock icon and does not appear in the application
        // switcher, so a window that slips behind another one cannot be
        // brought back the ways a person would try. Floating keeps it in
        // reach, and closing it is the way it goes away — the same reasoning
        // `OnboardingWindowController` already applies to first launch.
        window.level = .floating
        // Advisory. `NSHostingView` brings its own constraints, and the floor
        // the user actually meets is whatever SwiftUI derives from the split
        // view and its content — measured at 608 points wide, wherever this
        // line is placed and whatever it asks for. It is kept because it is
        // the floor for the height, which SwiftUI does not constrain.
        window.contentMinSize = NSSize(width: 700, height: 380)
        window.contentView = NSHostingView(
            rootView: SettingsView(
                frecency: frecency,
                access: access,
                onShortcutChanged: onShortcutChanged,
                bookmarks: bookmarks,
                applications: applications,
                pluginIndex: pluginIndex,
                configuration: configuration,
                secrets: secrets,
                updates: updates,
                onPreviewHUD: onPreviewHUD
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

        // Nothing holds the keyboard until the user gives it to something.
        // AppKit otherwise hands it to the first view that will take it, which
        // here is the shortcut recorder — and a recorder with the keyboard is
        // a recorder that says "Press a shortcut…" over the shortcut the user
        // already has, before they have touched anything.
        window.makeFirstResponder(nil)
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
