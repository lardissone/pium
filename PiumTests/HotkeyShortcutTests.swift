import Testing
import AppKit
import Carbon.HIToolbox
@testable import Pium

@Suite("HotkeyShortcut")
struct HotkeyShortcutTests {
    @Test func defaultShortcutIsOptionSpace() {
        #expect(HotkeyShortcut.optionSpace.keyCode == UInt16(kVK_Space))
        #expect(HotkeyShortcut.optionSpace.modifiers == .option)
        #expect(HotkeyShortcut.optionSpace.displayString == "⌥ Space")
    }

    /// Modifier symbols follow the order macOS uses in menus, regardless of
    /// the order they were pressed in.
    @Test func displayStringUsesStandardModifierOrder() {
        let shortcut = HotkeyShortcut(
            keyCode: UInt16(kVK_ANSI_K),
            modifiers: [.command, .shift, .control, .option],
            keyLabel: "K"
        )
        #expect(shortcut.displayString == "⌃ ⌥ ⇧ ⌘ K")
    }

    /// A combination without Control, Option, or Command would swallow
    /// ordinary typing system-wide, so it is rejected.
    @Test(arguments: [
        (NSEvent.ModifierFlags.shift.rawValue, false),
        (NSEvent.ModifierFlags([]).rawValue, false),
        (NSEvent.ModifierFlags.option.rawValue, true),
        (NSEvent.ModifierFlags.command.rawValue, true),
        (NSEvent.ModifierFlags.control.rawValue, true),
        (NSEvent.ModifierFlags([.shift, .command]).rawValue, true),
    ])
    func validityRequiresAnAcceleratorModifier(modifierRawValue: UInt, expected: Bool) {
        let shortcut = HotkeyShortcut(
            keyCode: 0,
            modifiers: NSEvent.ModifierFlags(rawValue: modifierRawValue),
            keyLabel: "A"
        )
        #expect(shortcut.isValid == expected)
    }

    @Test func carbonModifiersMapEachFlag() {
        let shortcut = HotkeyShortcut(
            keyCode: 0,
            modifiers: [.command, .option],
            keyLabel: "A"
        )
        #expect(shortcut.carbonModifiers == UInt32(cmdKey) | UInt32(optionKey))
    }

    /// Non-device-independent bits, such as the left/right variants AppKit
    /// sets, must not survive: otherwise two presses of the same physical key
    /// produce two different stored shortcuts.
    @Test func initialiserDropsDeviceSpecificFlags() {
        let raw = NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20
        )
        let shortcut = HotkeyShortcut(keyCode: 0, modifiers: raw, keyLabel: "A")
        #expect(shortcut.modifiers == .option)
    }

    @Test func roundTripsThroughCoding() throws {
        let original = HotkeyShortcut.optionSpace
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyShortcut.self, from: data)
        #expect(decoded == original)
    }
}
