import Testing
import AppKit
import Carbon.HIToolbox
@testable import Pium

@Suite("GlobalHotkeyController")
@MainActor
struct GlobalHotkeyControllerTests {
    /// Combinations no sane application claims.
    ///
    /// The tests run inside the app itself, which registers the real launcher
    /// shortcut at launch, so using `.optionSpace` here would collide with the
    /// application under test and fail with `eventHotKeyExistsErr`. These
    /// exercise the controller's behaviour, not one particular key.
    private static let unclaimed = HotkeyShortcut(
        keyCode: UInt16(kVK_F13),
        modifiers: [.control, .option, .shift, .command],
        keyLabel: "F13"
    )
    private static let otherUnclaimed = HotkeyShortcut(
        keyCode: UInt16(kVK_F14),
        modifiers: [.control, .option, .shift, .command],
        keyLabel: "F14"
    )

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

        try controller.register(Self.unclaimed) {}
        #expect(controller.registeredShortcut == Self.unclaimed)
    }

    /// Registering again replaces the previous combination rather than stacking
    /// a second registration, so an old shortcut cannot keep firing.
    @Test func registeringAgainReplacesThePreviousShortcut() throws {
        let controller = GlobalHotkeyController()
        defer { controller.unregister() }

        try controller.register(Self.unclaimed) {}
        try controller.register(Self.otherUnclaimed) {}

        #expect(controller.registeredShortcut == Self.otherUnclaimed)
    }

    /// A rejected shortcut must leave the previous registration alone, because
    /// validation happens before anything is torn down.
    @Test func aRejectedShortcutLeavesThePreviousRegistrationIntact() throws {
        let controller = GlobalHotkeyController()
        defer { controller.unregister() }

        try controller.register(Self.unclaimed) {}

        let unsafe = HotkeyShortcut(keyCode: 0, modifiers: .shift, keyLabel: "A")
        #expect(throws: GlobalHotkeyController.RegistrationError.missingRequiredModifier) {
            try controller.register(unsafe) {}
        }

        #expect(controller.registeredShortcut == Self.unclaimed)
    }

    /// The system rejects a combination someone else already owns, and that
    /// rejection must surface rather than be swallowed.
    ///
    /// The conflict is created here rather than relying on the shortcut the
    /// host application registers at launch, because that one is whatever the
    /// developer last saved in Settings.
    @Test func aShortcutAlreadyOwnedBySomeoneElseIsReportedAsRejected() throws {
        let owner = GlobalHotkeyController()
        defer { owner.unregister() }
        try owner.register(Self.unclaimed) {}

        let contender = GlobalHotkeyController()
        defer { contender.unregister() }

        #expect(throws: GlobalHotkeyController.RegistrationError.self) {
            try contender.register(Self.unclaimed) {}
        }
        #expect(contender.registeredShortcut == nil)
    }
}
