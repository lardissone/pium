import Testing
import AppKit
import Carbon.HIToolbox
@testable import Pium

@Suite("GlobalHotkeyController")
@MainActor
struct GlobalHotkeyControllerTests {
    /// A shortcut without Control, Option, or Command is rejected before it
    /// reaches the system, because registering it would intercept ordinary
    /// typing in every application.
    @Test func registrationRejectsAShortcutWithoutAnAcceleratorModifier() {
        let controller = GlobalHotkeyController()
        let unsafe = HotkeyShortcut(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: .shift,
            keyLabel: "A"
        )

        #expect(throws: GlobalHotkeyController.RegistrationError.missingRequiredModifier) {
            try controller.register(unsafe) {}
        }
        #expect(controller.registeredShortcut == nil)
    }

    @Test func unregisteringWithoutRegisteringIsHarmless() {
        let controller = GlobalHotkeyController()
        controller.unregister()
        #expect(controller.registeredShortcut == nil)
    }

    @Test func registeringRecordsTheShortcut() throws {
        let controller = GlobalHotkeyController()
        defer { controller.unregister() }

        try controller.register(.optionSpace) {}
        #expect(controller.registeredShortcut == .optionSpace)
    }

    /// Registering again replaces the previous combination rather than stacking
    /// a second registration, so an old shortcut cannot keep firing.
    @Test func registeringAgainReplacesThePreviousShortcut() throws {
        let controller = GlobalHotkeyController()
        defer { controller.unregister() }

        try controller.register(.optionSpace) {}
        let replacement = HotkeyShortcut(
            keyCode: UInt16(kVK_ANSI_P),
            modifiers: [.control, .option],
            keyLabel: "P"
        )
        try controller.register(replacement) {}

        #expect(controller.registeredShortcut == replacement)
    }

    /// A rejected shortcut must leave nothing behind, or the app ends up with a
    /// registration it does not know about.
    @Test func aRejectedShortcutLeavesNoRegistration() throws {
        let controller = GlobalHotkeyController()
        defer { controller.unregister() }

        try controller.register(.optionSpace) {}

        let unsafe = HotkeyShortcut(keyCode: 0, modifiers: .shift, keyLabel: "A")
        #expect(throws: GlobalHotkeyController.RegistrationError.missingRequiredModifier) {
            try controller.register(unsafe) {}
        }

        // The valid registration survives, because validation happens before
        // anything is torn down.
        #expect(controller.registeredShortcut == .optionSpace)
    }
}
