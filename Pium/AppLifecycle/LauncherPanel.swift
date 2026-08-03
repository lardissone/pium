import AppKit

/// Borderless floating window that hosts the launcher.
///
/// It becomes key so the search field receives typing, but is a non-activating
/// panel so Pium never becomes the foreground application and the user's
/// previous app keeps its active window chrome.
final class LauncherPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Without this the panel disappears the moment Pium is not frontmost,
        // which is its normal state.
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Appear over full-screen spaces without dragging the user out of them.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Panel appearance is animated in SwiftUI, so AppKit must not add its own.
        animationBehavior = .none
    }

    // A borderless window refuses key status by default; the search field needs it.
    override var canBecomeKey: Bool { true }

    // Main status would make Pium the foreground app, which is the one thing
    // this panel exists to avoid.
    override var canBecomeMain: Bool { false }
}
