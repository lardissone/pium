import AppKit
import Carbon.HIToolbox

/// Registers one system-wide key combination.
///
/// `RegisterEventHotKey` is the only documented way to receive a system-wide
/// shortcut without the Accessibility permission that
/// `NSEvent.addGlobalMonitorForEvents` requires. The product forbids asking for
/// that permission, so Carbon it is. Everything Carbon-specific is confined to
/// this file: if a modern replacement appears, one file changes.
@MainActor
final class GlobalHotkeyController {
    enum RegistrationError: Error, Equatable {
        /// The combination lacks Control, Option, and Command, and would
        /// swallow ordinary typing system-wide.
        case missingRequiredModifier
        /// macOS refused the registration, in practice because another
        /// application already owns this combination.
        case rejectedBySystem(OSStatus)
    }

    /// Four-character code identifying Pium as the owner of its hotkeys.
    private static let signature: OSType = 0x5049_554D  // 'PIUM'

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var pressHandler: (() -> Void)?

    private(set) var registeredShortcut: HotkeyShortcut?

    /// Replaces any existing registration with `shortcut`.
    ///
    /// Validation happens before anything is torn down, so a rejected shortcut
    /// leaves an existing valid registration intact. A failure from macOS
    /// itself unwinds fully, so nothing stays half-registered.
    func register(_ shortcut: HotkeyShortcut, onPress: @escaping () -> Void) throws {
        guard shortcut.isValid else { throw RegistrationError.missingRequiredModifier }

        unregister()
        pressHandler = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            unregister()
            throw RegistrationError.rejectedBySystem(status)
        }

        registeredShortcut = shortcut
    }

    /// Releases the Carbon registration. Safe to call when nothing is
    /// registered, and safe to call twice.
    ///
    /// There is no `deinit` counterpart: the controller is owned by the
    /// application delegate for the whole process lifetime, and a `deinit` on a
    /// main-actor-isolated class cannot touch this state under Swift 6.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        pressHandler = nil
        registeredShortcut = nil
    }

    fileprivate func handleHotKeyPressed() {
        pressHandler?()
    }
}

/// Carbon requires a plain C function pointer, which cannot capture context,
/// so the controller travels through `userData`. Carbon delivers hot key events
/// on the main run loop, which is why assuming main-actor isolation is safe.
private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotkeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    MainActor.assumeIsolated {
        controller.handleHotKeyPressed()
    }
    return noErr
}
