import AppKit
import Carbon.HIToolbox

/// A system-wide key combination: one key plus its modifier flags.
///
/// Modifier flags are stored as a raw value rather than `NSEvent.ModifierFlags`
/// so the type is trivially `Codable` and `Sendable`.
struct HotkeyShortcut: Codable, Equatable, Sendable {
    /// Virtual key code as defined by `Carbon.HIToolbox` (`kVK_*`). Key codes
    /// are positional, so they survive a keyboard layout change.
    let keyCode: UInt16

    /// Raw value of `NSEvent.ModifierFlags`, reduced to the device-independent set.
    let modifierRawValue: UInt

    /// Label for the key, captured from the event that recorded this shortcut.
    ///
    /// ponytail: taken from the recording event rather than translated through
    /// `UCKeyTranslate`, which means the label goes stale if the user changes
    /// keyboard layout after recording. Switch to `UCKeyTranslate` against the
    /// current layout if that ever bothers anyone.
    let keyLabel: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .rawValue
        self.keyLabel = keyLabel
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    /// The product default.
    static let optionSpace = HotkeyShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: .option,
        keyLabel: "Space"
    )

    /// What a development build starts on.
    static let controlOptionSpace = HotkeyShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: [.control, .option],
        keyLabel: "Space"
    )

    /// The combination a build offers before the user has chosen one.
    ///
    /// `RegisterEventHotKey` gives a combination to one process: whichever
    /// copy asks second is refused and never hears its shortcut. Starting a
    /// development build on a different combination is what lets it and an
    /// installed copy both answer.
    static var productDefault: HotkeyShortcut {
        AppIdentity.current.isRelease ? .optionSpace : .controlOptionSpace
    }
}

extension HotkeyShortcut {
    /// Human-readable form such as `⌥ Space`, using the modifier order macOS
    /// uses in menus.
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyLabel)
        return parts.joined(separator: " ")
    }

    /// Whether this combination is safe to register system-wide.
    ///
    /// Shift alone, or no modifier at all, would intercept ordinary typing in
    /// every application.
    var isValid: Bool {
        !modifiers.isDisjoint(with: [.control, .option, .command])
    }

    /// Modifier mask in the form `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }
}
