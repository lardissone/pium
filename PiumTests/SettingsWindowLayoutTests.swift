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

/// Every section of Settings has to be reachable at the size it opens at.
///
/// PIUM-132: the sections used to be tabs, which macOS 26 draws across the
/// title bar and collapses into an overflow chevron when they do not fit.
/// Settings opened at 620 points and the tabs needed 680, so a first run
/// showed no navigation at all — and the threshold moved with the language,
/// because the six Spanish labels render some 50 points wider than the
/// English ones.
///
/// They are a list beside the content now, which has no width at which it
/// hides anything.
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

    private func views(in content: NSView, named fragment: String) -> [NSView] {
        descendants(of: content).filter { "\(type(of: $0))".contains(fragment) }
    }

    /// One row per section. A `List` becomes a table, and its rows are the
    /// closest thing to "what the user can click" that AppKit will admit to —
    /// SwiftUI draws the labels themselves without creating views for them.
    private func listedSections(in content: NSView) -> Int {
        views(in: content, named: "ListTableRowView").count
    }

    @Test func everySectionIsListedAtTheSizeSettingsOpensAt() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        let content = try #require(window.contentView)

        #expect(
            listedSections(in: content) == SettingsSection.allCases.count,
            """
            \(listedSections(in: content)) of \(SettingsSection.allCases.count) \
            sections are listed at \(content.frame.size). Settings has hidden \
            part of itself, which is PIUM-132 returning.
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
    /// is told. So the window is squeezed and the sections counted again.
    @Test func everySectionSurvivesTheSmallestWindowTheUserCanMake() throws {
        let window = try #require(presentSettings(), "Settings did not open")
        #expect(window.contentLayoutRect.width >= 700, "Settings opened narrower than intended.")

        // Far below any floor, so AppKit settles on its own minimum.
        window.setContentSize(NSSize(width: 200, height: 200))
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // The list itself, not the row count. A table only builds rows for the
        // ones on screen, so a short window legitimately reports four of six —
        // the other two are a scroll away, which is reachable. What must never
        // happen is the list going away.
        let content = try #require(window.contentView)
        let sidebar = views(in: content, named: "OutlineListRepresentable")
            .map(\.frame.width).max() ?? 0

        #expect(
            sidebar >= 100,
            """
            Squeezed to \(content.frame.size), the section list is \(sidebar) \
            points wide. Settings has become unnavigable by dragging, which is \
            the shape PIUM-132 took.
            """
        )
        #expect(
            listedSections(in: content) > 0,
            "No sections are listed at \(content.frame.size)."
        )

        window.orderOut(nil)
    }

    /// Opening Settings must not look like it is waiting for a keystroke.
    ///
    /// The shortcut recorder draws "Press a shortcut…" whenever it holds the
    /// keyboard, which is honest — it is listening. The trouble is that AppKit
    /// hands the keyboard to the first view that will take it when a window
    /// opens, and the recorder is that view. So Settings opened claiming to be
    /// recording, and the shortcut the user actually has was nowhere on screen
    /// until they pressed something.
    @Test func openingSettingsDoesNotStartRecordingAShortcut() throws {
        let window = try #require(presentSettings(), "Settings did not open")

        let isRecorder = window.firstResponder is ShortcutRecorderView.RecorderView
        #expect(
            !isRecorder,
            """
            The shortcut recorder holds the keyboard the moment Settings opens, \
            so it draws "Press a shortcut…" over the shortcut the user already \
            has.
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

        let sidebar = views(in: content, named: "OutlineListRepresentable")
            .map(\.frame.width).max() ?? 0
        #expect(sidebar >= 100, "The section list is \(sidebar) points wide.")

        let pane = content.frame.width - sidebar
        let section = views(in: content, named: "HostingScrollView")
            .map(\.frame.width).max() ?? 0

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
