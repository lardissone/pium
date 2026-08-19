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
            bookmarks: BookmarkStore(),
            applications: ApplicationIndex(),
            favicons: FaviconStore(),
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

    /// The Bookmarks section on its own, with something in it.
    ///
    /// Separate from the probe above because the section list is chosen by a
    /// click, and nothing here can click. Hosting the one section directly is
    /// what makes its own layout — the split, the form, the line under the
    /// destination field — visible without driving the whole window.
    ///
    /// Its store is an isolated defaults domain, so photographing this never
    /// touches the bookmarks the developer actually has.
    @Test func holdBookmarksOpenForCapture() throws {
        let suiteName = "com.lardissone.pium.look.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = BookmarkStore(preferences: Preferences(defaults: defaults))
        store.add(
            Bookmark(
                name: "Search YouTube",
                destination: .link("https://www.youtube.com/results?search_query={{input}}"),
                keywords: ["yt", "video"]
            )
        )
        store.add(Bookmark(name: "Notes", destination: .path("~/Documents")))

        let applications = ApplicationIndex()
        applications.refresh()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bookmarks look probe"
        window.level = .floating
        window.contentView = NSHostingView(
            rootView: BookmarksSettingsView(
                store: store, applications: applications, favicons: FaviconStore()
            )
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        RunLoop.current.run(until: Date().addingTimeInterval(2))
        print("LOOK  window=\(window.windowNumber)")
        RunLoop.current.run(until: Date().addingTimeInterval(30))
        window.orderOut(nil)
    }
}
