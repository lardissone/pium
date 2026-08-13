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

/// Settings has to be navigable, and readable, at the size it opens at.
///
/// PIUM-132: with its sections as tabs, macOS drew them across the title bar
/// and collapsed all six into a `»` overflow button whenever the window was
/// narrower than about 680 points. Settings opened at 620, so a first run
/// showed no navigation at all until the window was dragged wider — and the
/// threshold moved with the language, because the six Spanish labels render
/// some 50 points wider than the English ones.
///
/// A sidebar does not have that failure: it lives in the content view, where
/// its width is its own rather than whatever the title bar has left over.
@MainActor
@Suite("Settings window layout")
struct SettingsWindowLayoutTests {
    /// Opens Settings the way `AppDelegate` does, from a first run.
    ///
    /// The saved frame is cleared first. Without that these measure whatever
    /// size the machine running them last left the window at, which is the
    /// user's business and not the default this is about.
    private func presentSettings() -> NSWindow? {
        NSWindow.removeFrame(usingName: SettingsWindowController.frameAutosaveName)

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

    /// SwiftUI names a pane's hosting view after the style it was given, which
    /// is what tells a sidebar from a detail pane — they are otherwise the
    /// same kind of view.
    private func sidebarWidth(in content: NSView) -> CGFloat {
        descendants(of: content)
            .filter { "\(type(of: $0))".contains("SidebarStyleContext") }
            .map(\.frame.width)
            .max() ?? 0
    }

    @Test func theSectionListIsPresentAtTheSizeSettingsOpensAt() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        let content = try #require(window.contentView)
        let sidebar = sidebarWidth(in: content)

        // A pane of zero width is present and useless, so the width is
        // asserted rather than the existence. The measured sidebar is about
        // 140 points; under 100 is collapsed rather than laid out.
        #expect(
            sidebar >= 100,
            """
            The Settings sidebar is \(sidebar) points wide at \
            \(content.frame.size). Its sections are unreachable until the \
            window is resized, which is PIUM-132 returning.
            """
        )

        window.orderOut(nil)
    }

    /// Opening wide enough is half of it. The other half is that dragging the
    /// window as small as it goes must not take the sections away again, which
    /// is exactly what the title-bar tabs did.
    ///
    /// `contentMinSize` is not the thing to assert: `NSHostingView` brings its
    /// own constraints and the floor SwiftUI derives wins, whatever the window
    /// is told. So the window is squeezed and the sidebar looked for again.
    @Test func theSectionListSurvivesTheSmallestWindowTheUserCanMake() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        #expect(window.contentLayoutRect.width >= 700, "Settings opened narrower than intended.")

        // Far below any floor, so AppKit settles on its own minimum.
        window.setContentSize(NSSize(width: 200, height: 200))
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let content = try #require(window.contentView)
        let sidebar = sidebarWidth(in: content)
        #expect(
            sidebar >= 100,
            """
            Squeezed to \(content.frame.size), the sidebar is \(sidebar) points \
            wide. Settings has become unnavigable by dragging, which is the \
            shape PIUM-132 took with tabs.
            """
        )

        window.orderOut(nil)
    }

    /// A section that does not use the room it is given reads as broken even
    /// though everything works. General carried a fixed 460-point frame from
    /// when it was the only section and that number sized the whole window;
    /// beside a sidebar, in a window twice as wide, it sat stranded in the
    /// middle with more margin than content.
    @Test func aSectionFillsTheRoomItIsGiven() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        let content = try #require(window.contentView)

        let pane = content.frame.width - sidebarWidth(in: content)
        let section = descendants(of: content)
            .filter { "\(type(of: $0))".contains("HostingScrollView") }
            .map(\.frame.width)
            .max() ?? 0

        // Generous, because a section is inset from its pane and so always
        // narrower. This catches one pinned to a fixed width, not one padded.
        #expect(
            section >= pane * 0.8,
            """
            The section is \(section) points wide inside a \(pane)-point pane. \
            A fixed frame has come back, and Settings is mostly margin.
            """
        )

        window.orderOut(nil)
    }
}
