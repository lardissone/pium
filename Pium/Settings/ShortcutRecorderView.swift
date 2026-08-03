import AppKit
import SwiftUI

/// A control that records the next key combination the user presses.
///
/// SwiftUI cannot observe raw key events for arbitrary combinations, so this
/// wraps a small `NSView` that becomes first responder while recording.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: HotkeyShortcut

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = { shortcut = $0 }
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.shortcut = shortcut
    }

    final class RecorderView: NSView {
        /// Virtual key code for Escape, which abandons recording.
        private static let escapeKeyCode: UInt16 = 53

        var onRecord: ((HotkeyShortcut) -> Void)?

        var shortcut: HotkeyShortcut = .optionSpace {
            didSet { needsDisplay = true }
        }

        private var isRecording = false {
            didSet { needsDisplay = true }
        }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == Self.escapeKeyCode {
                // Abandon recording and keep the existing shortcut.
                isRecording = false
                window?.makeFirstResponder(nil)
                return
            }

            let candidate = HotkeyShortcut(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                keyLabel: Self.label(for: event)
            )

            // Reject silently and keep recording, so the user can simply try a
            // different combination without dismissing an alert.
            guard candidate.isValid else { return }

            shortcut = candidate
            onRecord?(candidate)
            isRecording = false
            window?.makeFirstResponder(nil)
        }

        /// Display label for the pressed key, taken from the event so it matches
        /// the user's actual keyboard layout.
        private static func label(for event: NSEvent) -> String {
            switch Int(event.keyCode) {
            case 49: "Space"
            case 36: "Return"
            case 48: "Tab"
            case 51: "Delete"
            case 123: "←"
            case 124: "→"
            case 125: "↓"
            case 126: "↑"
            default: event.charactersIgnoringModifiers?.uppercased() ?? "?"
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let background = isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.controlBackgroundColor
            background.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

            let title = isRecording
                ? String(localized: "settings.shortcut.recording")
                : shortcut.displayString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: isRecording
                    ? NSColor.secondaryLabelColor
                    : NSColor.labelColor,
            ]

            let size = title.size(withAttributes: attributes)
            title.draw(
                at: NSPoint(
                    x: bounds.midX - size.width / 2,
                    y: bounds.midY - size.height / 2
                ),
                withAttributes: attributes
            )
        }

        override func accessibilityLabel() -> String? {
            String(localized: "settings.shortcut.accessibilityLabel")
        }

        override func accessibilityValue() -> Any? {
            shortcut.displayString
        }
    }
}
