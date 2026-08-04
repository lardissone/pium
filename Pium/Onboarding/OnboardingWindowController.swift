import AppKit
import SwiftUI

/// Hosts onboarding in a normal, closable window. Pium has no other window of
/// this kind, so this controller exists only for first launch.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func present(shortcut: HotkeyShortcut, onFinish: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "onboarding.windowTitle")
        window.isReleasedWhenClosed = false
        // Pium has no Dock icon and does not appear in the application
        // switcher, so a window that slips behind another one cannot be
        // brought back. Floating keeps first launch reachable.
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(
            rootView: OnboardingView(shortcut: shortcut) { [weak self] in
                onFinish()
                self?.dismiss()
            }
        )

        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
