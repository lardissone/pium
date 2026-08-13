import AppKit
import SwiftUI
import Testing
@testable import Pium

@MainActor
private final class ProbeUpdates: UpdateAvailability {
    var pendingUpdate: PendingUpdate?
    var automaticallyChecks = true
    var lastCheck: Date?
    func checkForUpdates() {}
    func installPendingUpdate() {}
}

/// Opens the real Settings window and holds it there, so its appearance can be
/// checked without anyone at the keyboard.
///
/// Nothing in-process renders it faithfully: `cacheDisplay` draws the AppKit
/// view tree and SwiftUI is not in it, and rendering the layer tree misses the
/// section list and draws controls as blank shapes. What works is
/// `screencapture` run from a shell that has screen-recording permission,
/// against the window this leaves open:
///
///     PIUM_LOOK=1 xcodebuild test -project Pium.xcodeproj -scheme Pium \
///       -destination 'platform=macOS' -only-testing:PiumTests/SettingsLookProbe &
///     # then, once the window is up:
///     screencapture -l<window-id> -o -t png /tmp/settings.png
///
/// Off unless asked for: it opens a window, waits half a minute, and asserts
/// nothing.
@MainActor
@Suite("Settings look probe", .enabled(if: ProcessInfo.processInfo.environment["PIUM_LOOK"] == "1"))
struct SettingsLookProbe {
    @Test func holdOpenForCapture() throws {
        NSWindow.removeFrame(usingName: SettingsWindowController.frameAutosaveName)
        let controller = SettingsWindowController()
        controller.present(
            frecency: FrecencyStore(),
            access: ProtectedFolderAccess(preferences: .shared),
            onShortcutChanged: { _ in },
            pluginIndex: PluginIndex(),
            configuration: PluginConfigurationStore(),
            secrets: KeychainSecretStore(),
            updates: ProbeUpdates(),
            onPreviewHUD: {}
        )
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        let window = try #require(
            NSApp.windows.first { $0.title == String(localized: "settings.windowTitle") }
        )
        print("LOOK  window=\(window.windowNumber)")
        RunLoop.current.run(until: Date().addingTimeInterval(30))
        window.orderOut(nil)
    }
}
