import AppKit
import SwiftUI
import Testing
@testable import Pium

@MainActor
private final class StubUpdates: UpdateAvailability {
    var pendingUpdate: PendingUpdate?
    var automaticallyChecks = true
    var lastCheck: Date?
    func checkForUpdates() {}
    func installPendingUpdate() {}
}

/// Settings has to be navigable at the size it opens at.
///
/// PIUM-132: with its sections as tabs, macOS drew them across the title bar
/// and collapsed all six into a `»` overflow button whenever the window was
/// narrower than about 680 points. Settings opened at 620, so every first run
/// showed no navigation at all until the window was dragged wider — and the
/// threshold moved with the language, because Spanish labels are some 50
/// points longer than English ones.
///
/// A sidebar does not have that failure: it lives in the content view, where
/// its width is its own rather than whatever the title bar has left over.
/// This asserts the property that made the difference, at the real window's
/// real size, by driving the controller the app drives.
@MainActor
@Suite("Settings window layout")
struct SettingsWindowLayoutTests {
    /// Opens Settings the way `AppDelegate` does and hands back its window.
    private func presentSettings() -> NSWindow? {
        let controller = SettingsWindowController()
        controller.present(
            frecency: FrecencyStore(),
            access: ProtectedFolderAccess(preferences: .shared),
            onShortcutChanged: { _ in },
            pluginIndex: PluginIndex(),
            configuration: PluginConfigurationStore(),
            secrets: KeychainSecretStore(),
            updates: StubUpdates(),
            onPreviewHUD: {}
        )
        // Let SwiftUI lay out. Never `layoutSubtreeIfNeeded()`, which recurses
        // and hangs the test host.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        return NSApp.windows.first { $0.title == String(localized: "settings.windowTitle") }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }

    @Test func theSectionListIsPresentAtTheSizeSettingsOpensAt() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        let content = try #require(window.contentView)

        // The sidebar is a pane of the navigation split view, and SwiftUI
        // names its hosting view after the style it was given. Matching on
        // that is what distinguishes a sidebar from a detail pane, which is
        // otherwise the same kind of view.
        let sidebars = descendants(of: content).filter {
            "\(type(of: $0))".contains("SidebarStyleContext")
        }

        #expect(
            !sidebars.isEmpty,
            """
            No sidebar in the Settings content view at \(content.frame.size). \
            Its sections are unreachable until the window is resized, which is \
            PIUM-132 returning.
            """
        )

        // A pane of zero width is present and useless. The measured sidebar is
        // about 140 points; anything under 100 is collapsed rather than laid
        // out.
        let widest = sidebars.map(\.frame.width).max() ?? 0
        #expect(widest >= 100, "The sidebar is \(widest) points wide, which is collapsed.")

        window.orderOut(nil)
    }

    /// Opening wide enough is half of it. The other half is that dragging the
    /// window as small as it goes must not take the sections away again, which
    /// is exactly what the title-bar tabs did.
    ///
    /// `contentMinSize` is not the thing to assert: `NSHostingView` brings its
    /// own constraints and the floor SwiftUI derives wins, whatever the window
    /// is told. So the window is squeezed and the sidebar is looked for again.
    @Test func theSectionListSurvivesTheSmallestWindowTheUserCanMake() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        #expect(window.contentLayoutRect.width >= 700, "Settings opened narrower than intended.")

        // Far below any floor, so AppKit settles on its own minimum.
        window.setContentSize(NSSize(width: 200, height: 200))
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let content = try #require(window.contentView)
        let sidebars = descendants(of: content).filter {
            "\(type(of: $0))".contains("SidebarStyleContext")
        }
        let widest = sidebars.map(\.frame.width).max() ?? 0

        #expect(
            widest >= 100,
            """
            Squeezed to \(content.frame.size), the sidebar is \(widest) points \
            wide. Settings has become unnavigable by dragging, which is the \
            shape PIUM-132 took with tabs.
            """
        )

        window.orderOut(nil)
    }
}
