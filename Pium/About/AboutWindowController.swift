import AppKit
import SwiftUI

/// Hosts About in a window Pium owns, for the same reason Settings is:
/// `LSUIElement` leaves the app without a standard application menu, so
/// there is no free `Pium ▸ About` and nothing to receive the standard
/// panel's action. See `SettingsWindowController`.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func present() {
        // Reuse the existing window so the menu item raises About rather than
        // stacking a second copy.
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Not resizable: the content is fixed text and one image at a fixed
        // width, so there is nothing for a larger window to reveal.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "about.windowTitle")
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: AboutView())
        window.contentView = hosting
        // Sized from the content: unlike Settings, this view reports a usable
        // fitting height, and hardcoding one would clip a longer translation.
        window.setContentSize(hosting.fittingSize)
        window.center()

        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
