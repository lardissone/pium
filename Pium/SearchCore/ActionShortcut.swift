import SwiftUI

/// A key combination that runs an action from the launcher.
///
/// Distinct from `HotkeyShortcut`, which is a Carbon-registered system-wide
/// combination stored in preferences. This one is compared against SwiftUI
/// `KeyPress` values inside the app and is never persisted, so it stores what
/// SwiftUI reports rather than a virtual key code.
struct ActionShortcut: Sendable, Equatable {
    enum Key: Sendable, Equatable {
        case character(Character)
        case `return`
    }

    struct Modifiers: OptionSet, Sendable, Equatable {
        let rawValue: Int

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let key: Key
    let modifiers: Modifiers

    /// The primary action of every result.
    static let returnKey = ActionShortcut(key: .return, modifiers: [])
    /// The second action of every result type the PRD lists.
    static let commandReturn = ActionShortcut(key: .return, modifiers: [.command])
    /// Opens the contextual action menu.
    static let commandK = ActionShortcut(key: .character("k"), modifiers: [.command])

    /// Whether a pressed combination runs this action.
    ///
    /// Modifiers must match exactly: `⇧⌘Return` is not `⌘Return`, and running
    /// the wrong action because of a stray modifier is worse than doing
    /// nothing. Letters compare case-insensitively, because the character the
    /// system reports changes when Shift is held.
    func matches(key otherKey: Key, modifiers otherModifiers: Modifiers) -> Bool {
        guard modifiers == otherModifiers else { return false }
        switch (key, otherKey) {
        case (.return, .return):
            return true
        case (.character(let mine), .character(let theirs)):
            return String(mine).lowercased() == String(theirs).lowercased()
        default:
            return false
        }
    }

    /// Human-readable form such as `⌘⏎`, using the modifier order macOS uses in
    /// its own menus.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        switch key {
        case .return: result += "⏎"
        case .character(let character): result += String(character).uppercased()
        }
        return result
    }
}

extension ActionShortcut.Modifiers {
    /// Bridges what SwiftUI reports on a `KeyPress` into the stored form.
    init(_ eventModifiers: EventModifiers) {
        self = []
        if eventModifiers.contains(.control) { insert(.control) }
        if eventModifiers.contains(.option) { insert(.option) }
        if eventModifiers.contains(.shift) { insert(.shift) }
        if eventModifiers.contains(.command) { insert(.command) }
    }
}
