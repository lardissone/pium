import AppKit
import SwiftUI

/// Owns the launcher panel: when it appears, where, and what dismisses it.
@MainActor
final class LauncherPanelController: NSObject {
    private let panel: LauncherPanel

    var isVisible: Bool { panel.isVisible }

    override init() {
        let size = CGSize(
            width: Tokens.Size.panelWidth,
            height: Tokens.Size.searchFieldHeight
        )
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size))
        super.init()

        panel.contentView = NSHostingView(
            rootView: LauncherView { [weak self] in self?.hide() }
        )
        // `NSWindow.delegate` is weak, so this does not retain the controller.
        // Using the delegate rather than a NotificationCenter observer avoids
        // owning a token that would need cleaning up in a `deinit`, which a
        // main-actor-isolated class cannot have under Swift 6.
        panel.delegate = self
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let interval = Signposts.launcher.beginInterval("show")
        defer { Signposts.launcher.endInterval("show", interval) }

        moveToTargetScreen()
        // An accessory app must activate for its panel to take key status, but
        // because the panel is non-activating this does not steal the user's
        // foreground application.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Positions the panel on the display holding the focused window, near the
    /// upper third. The decision itself lives in `ScreenPlacement`, which is
    /// unit-tested; this reads live `NSScreen` state and nothing more.
    private func moveToTargetScreen() {
        let screens = NSScreen.screens
        let mainIndex = NSScreen.main.flatMap { screens.firstIndex(of: $0) }

        guard let targetIndex = ScreenPlacement.indexOfTargetScreen(
            mainIndex: mainIndex,
            mouseLocation: NSEvent.mouseLocation,
            frames: screens.map(\.frame)
        ) else {
            return
        }

        let origin = ScreenPlacement.origin(
            panelSize: panel.frame.size,
            in: screens[targetIndex].visibleFrame
        )
        panel.setFrameOrigin(origin)
    }
}

extension LauncherPanelController: NSWindowDelegate {
    /// Clicking or focusing another application dismisses the launcher.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
