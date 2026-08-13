import AppKit
import Observation
import SwiftUI

/// Owns the launcher panel: when it appears, where, and what dismisses it.
@MainActor
final class LauncherPanelController: NSObject {
    private let panel: LauncherPanel
    private let state: LauncherState
    private let coordinator: SearchCoordinator
    /// The same store the coordinator ranks against, so what is recorded here
    /// is what the next search sees.
    private let frecency: any FrecencyStoring
    /// Read for `activeRecord` alone: a run starting or ending changes how
    /// tall the panel needs to be, independently of the search results
    /// stream that is the only other thing that resizes it.
    private let executionManager: ExecutionManager
    private var searchTask: Task<Void, Never>?

    var isVisible: Bool { panel.isVisible }

    /// The display the launcher last opened on, which outlives the opening: a
    /// run started here can finish long after the panel closed, and whatever
    /// it puts on screen belongs where the user was looking when they asked
    /// for it.
    private(set) var targetScreen: NSScreen?

    /// `updates` reaches the launcher's state because PRD §13 shows a found
    /// version here, the next time the launcher opens.
    init(
        coordinator: SearchCoordinator,
        frecency: any FrecencyStoring,
        executionManager: ExecutionManager,
        updates: any UpdateAvailability
    ) {
        self.coordinator = coordinator
        self.frecency = frecency
        self.executionManager = executionManager
        state = LauncherState(updates: updates)
        let size = CGSize(
            width: Tokens.Size.panelWidth,
            height: Tokens.Size.searchFieldHeight
        )
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size))
        super.init()

        panel.contentView = NSHostingView(
            rootView: LauncherView(
                state: state,
                executionManager: executionManager,
                onDismiss: { [weak self] in self?.hide() },
                onQueryChanged: { [weak self] text in self?.runSearch(text) },
                onPerform: { [weak self] result, _ in self?.record(result) }
            )
        )
        // `NSWindow.delegate` is weak, so this does not retain the controller.
        // Using the delegate rather than a NotificationCenter observer avoids
        // owning a token that would need cleaning up in a `deinit`, which a
        // main-actor-isolated class cannot have under Swift 6.
        panel.delegate = self
        observeActiveRun()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let interval = Signposts.launcher.beginInterval("show")
        defer { Signposts.launcher.endInterval("show", interval) }

        // The view stays mounted while the panel is hidden, so the per-opening
        // reset has to be driven from here.
        state.prepareForPresentation()
        // The panel may still be expanded from the previous opening, and
        // placement is computed from its size, so shrink before positioning.
        panel.setContentSize(
            CGSize(width: Tokens.Size.panelWidth, height: Tokens.Size.searchFieldHeight)
        )
        moveToTargetScreen()
        // An accessory app must activate for its panel to take key status, but
        // because the panel is non-activating this does not steal the user's
        // foreground application.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Typing is not the only way the panel needs to be taller than the
        // search field: reopening while a plugin is running must show its
        // footer too (PRD §11), and nothing types anything on that path.
        resizePanelToContent()
        DebugLog.record(.launcher(.opened))
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        DebugLog.record(.launcher(.dismissed))
    }

    /// Applications and plugins search from the first character, so there is no
    /// debounce here. The file provider debounces itself.
    private func runSearch(_ text: String) {
        searchTask?.cancel()
        state.beginSearch()
        searchTask = Task { [weak self] in
            guard let self else { return }
            for await results in coordinator.search(text) {
                guard !Task.isCancelled else { return }
                state.setResults(results)
                resizePanelToContent()
            }
            // The stream is finished, so an empty list is now a fact rather
            // than a moment in the middle of one. A cancelled search says
            // nothing: a newer query is already in flight and owns the phase.
            guard !Task.isCancelled else { return }
            state.endSearch()
            resizePanelToContent()
        }
    }

    /// Only selections are learned from — never an abandoned query.
    private func record(_ result: SearchResult) {
        frecency.record(
            resultID: result.id,
            query: TextNormalizer.query(state.query),
            at: Date()
        )
    }

    /// Resizes the panel whenever a run starts or ends, so a plugin finishing
    /// while the launcher is sitting open shrinks the footer away instead of
    /// leaving a gap. Re-registers itself after every change: `Observation`
    /// tracking fires its `onChange` once and then stops watching.
    ///
    /// Only while the panel is visible — the view stays mounted behind a
    /// hidden panel (see `hide()`), so `activeRecord` keeps changing while
    /// nobody is looking, and there is nothing on screen to resize.
    private func observeActiveRun() {
        withObservationTracking { [weak self] in
            _ = self?.executionManager.activeRecord
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.panel.isVisible { self.resizePanelToContent() }
                self.observeActiveRun()
            }
        }
    }

    /// The panel grows and shrinks with the result list, keeping its top edge
    /// fixed so the search field does not jump under the cursor.
    private func resizePanelToContent() {
        guard let contentView = panel.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let fitting = contentView.fittingSize
        guard fitting.height > 0 else { return }
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(
                x: panel.frame.minX,
                y: top - fitting.height,
                width: Tokens.Size.panelWidth,
                height: fitting.height
            ),
            display: true
        )
    }

    /// Positions the panel on the display holding the focused window, near the
    /// upper third. The decision itself lives in `ScreenPlacement`, which is
    /// unit-tested; this reads live `NSScreen` state and nothing more.
    private func moveToTargetScreen() {
        let screens = NSScreen.screens
        let mainIndex = NSScreen.main.flatMap { screens.firstIndex(of: $0) }

        guard let targetIndex = ScreenPlacement.indexOfTargetScreen(
            mainIndex: mainIndex,
            mouseLocation: NSEvent.mouseLocation,
            frames: screens.map(\.frame)
        ) else {
            return
        }
        targetScreen = screens[targetIndex]

        let origin = ScreenPlacement.origin(
            panelSize: panel.frame.size,
            in: screens[targetIndex].visibleFrame
        )
        panel.setFrameOrigin(origin)
    }
}

extension LauncherPanelController: NSWindowDelegate {
    /// Clicking or focusing another application dismisses the launcher.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
