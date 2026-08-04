import Testing
@testable import Pium

@Suite("Action shortcuts")
struct ActionShortcutTests {
    /// The symbols are what the user reads in the footer and the menu, so the
    /// order has to match how macOS writes combinations in its own menus.
    @Test func displayUsesTheSystemModifierOrder() {
        #expect(ActionShortcut.returnKey.displayString == "⏎")
        #expect(ActionShortcut.commandReturn.displayString == "⌘⏎")
        #expect(ActionShortcut.commandK.displayString == "⌘K")
        #expect(
            ActionShortcut(key: .character("i"), modifiers: [.command, .shift])
                .displayString == "⇧⌘I"
        )
        #expect(
            ActionShortcut(key: .character("i"), modifiers: [.command, .option])
                .displayString == "⌥⌘I"
        )
    }

    @Test func aLetterIsShownUppercased() {
        #expect(ActionShortcut(key: .character("k"), modifiers: []).displayString == "K")
    }

    @Test func matchingRequiresTheSameKeyAndTheSameModifiers() {
        #expect(ActionShortcut.commandReturn.matches(key: .return, modifiers: [.command]))
        #expect(!ActionShortcut.commandReturn.matches(key: .return, modifiers: []))
        #expect(!ActionShortcut.returnKey.matches(key: .return, modifiers: [.command]))
        #expect(!ActionShortcut.commandK.matches(key: .character("j"), modifiers: [.command]))
    }

    /// A stray modifier must not run the wrong action: `⇧⌘Return` is not
    /// `⌘Return`.
    @Test func anExtraModifierDoesNotMatch() {
        #expect(!ActionShortcut.commandReturn.matches(
            key: .return, modifiers: [.command, .shift]
        ))
    }

    /// Letters are compared case-insensitively because the reported character
    /// changes when Shift is held.
    @Test func letterMatchingIgnoresCase() {
        #expect(ActionShortcut.commandK.matches(key: .character("K"), modifiers: [.command]))
    }
}
