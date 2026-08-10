import AppKit

/// A borderless floating panel showing one command's result.
///
/// Unlike the launcher's panel this never becomes key: a HUD appears while the
/// user is doing something else, and taking the keyboard from them would be a
/// bug. PRD §11 also has it outlive the launcher, so it is owned by
/// `HUDController` rather than by any window.
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
