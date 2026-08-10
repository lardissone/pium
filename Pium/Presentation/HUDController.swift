import AppKit
import SwiftUI

/// Owns the HUDs on screen: adds one, expires it, and keeps the stack tidy.
///
/// A HUD outlives the launcher that started it (PRD §11), so nothing about it
/// is tied to the panel controller. Panels are created on the first outcome
/// that needs one — never at launch, which would spend the launcher's latency
/// budget on a window nobody has asked for.
@MainActor
final class HUDController {
    private struct Entry {
        let panel: HUDPanel
        var expiry: Task<Void, Never>?
        /// The run this panel is showing progress for, while it is still
        /// showing progress — `nil` once it holds an outcome instead. This is
        /// what `finishRunning` uses to find the panel to replace.
        var runningID: UUID?
    }

    private static let spacing: CGFloat = 10

    private var entries: [Entry] = []
    private let anchor: () -> HUDAnchor
    private let runningDelay: Duration
    /// Runs whose HUD has not appeared yet — still inside `runningDelay`.
    /// Keyed by run id so `finishRunning` can cancel the wait for a run that
    /// finishes before its HUD would have shown.
    private var pendingRunning: [UUID: Task<Void, Never>] = [:]

    init(
        anchor: @escaping () -> HUDAnchor = { Preferences.shared.hudAnchor },
        runningDelay: Duration = .seconds(1)
    ) {
        self.anchor = anchor
        self.runningDelay = runningDelay
    }

    var visibleCount: Int { entries.count }

    /// The frames, newest first — what the layout tests read.
    var frames: [CGRect] { entries.map(\.panel.frame) }

    func show(_ presentation: HUDPresentation) {
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: .zero))
        applyOutcome(presentation, to: panel)
        let entry = Entry(
            panel: panel,
            expiry: expiryTask(for: panel, duration: presentation.duration),
            runningID: nil
        )
        entries.insert(entry, at: 0)
        panel.orderFrontRegardless()
        layout()
    }

    /// Called when a run starts. Nothing appears until `runningDelay` has
    /// passed — most runs finish before that, and a HUD that flashes and
    /// vanishes is worse than no HUD at all (PIUM-106). If the run is still
    /// going once the delay elapses, a HUD naming the plugin and counting its
    /// elapsed time appears, with `onCancel` behind its Cancel button.
    func showRunning(id: UUID, presentation: RunningPresentation, onCancel: @escaping () -> Void) {
        let delay = runningDelay
        pendingRunning[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.presentRunning(id: id, presentation: presentation, onCancel: onCancel)
        }
    }

    /// Called when a run ends, whatever it ended as.
    ///
    /// A run whose HUD never appeared — it finished inside `runningDelay` —
    /// simply has its wait cancelled; `presentation`, if any, then shows as a
    /// fresh HUD exactly as `show(_:)` always has. A run whose HUD is already
    /// on screen has it replaced in place rather than stacked under a new
    /// entry, or removed outright when `presentation` is `nil` — a cancelled
    /// run's existing policy of showing nothing.
    func finishRunning(id: UUID, with presentation: HUDPresentation?) {
        pendingRunning.removeValue(forKey: id)?.cancel()
        guard let index = entries.firstIndex(where: { $0.runningID == id }) else {
            if let presentation { show(presentation) }
            return
        }
        guard let presentation else {
            dismiss(entries[index].panel)
            return
        }
        let panel = entries[index].panel
        applyOutcome(presentation, to: panel)
        entries[index].runningID = nil
        entries[index].expiry = expiryTask(for: panel, duration: presentation.duration)
        layout()
    }

    func dismissAll() {
        for pending in pendingRunning.values { pending.cancel() }
        pendingRunning.removeAll()
        for entry in entries {
            entry.expiry?.cancel()
            entry.panel.orderOut(nil)
        }
        entries.removeAll()
    }

    private func presentRunning(id: UUID, presentation: RunningPresentation, onCancel: @escaping () -> Void) {
        pendingRunning[id] = nil
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: .zero))
        panel.contentView = NSHostingView(
            rootView: RunningHUDView(presentation: presentation, onCancel: onCancel)
        )
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
        entries.insert(Entry(panel: panel, expiry: nil, runningID: id), at: 0)
        panel.orderFrontRegardless()
        layout()
    }

    private func applyOutcome(_ presentation: HUDPresentation, to panel: HUDPanel) {
        panel.contentView = NSHostingView(
            rootView: HUDView(presentation: presentation) { [presentation] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(presentation.body, forType: .string)
            }
        )
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
    }

    private func expiryTask(for panel: HUDPanel, duration: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            // `self` is weak so this task cannot keep the controller alive,
            // but the reverse is not covered: if the controller were ever
            // deallocated while entries were still live, this closure would
            // find `self` gone and never reach `orderOut`, leaving the panel
            // on screen. `AppDelegate` holds the controller for the app's
            // whole lifetime, which is what makes that unreachable today —
            // a deliberate ceiling, not an oversight.
            self?.dismiss(panel)
        }
    }

    private func dismiss(_ panel: HUDPanel) {
        guard let index = entries.firstIndex(where: { $0.panel === panel }) else { return }
        entries[index].expiry?.cancel()
        entries[index].panel.orderOut(nil)
        entries.remove(at: index)
        layout()
    }

    /// Newest nearest the anchored edge; the rest drift toward the middle.
    ///
    /// Each panel is placed after the real heights of the ones already laid
    /// out this pass, not after its own — HUDs vary in height with how much a
    /// plugin printed, so a taller panel ahead of this one has to open a wider
    /// gap than a shorter one would.
    private func layout() {
        guard let screen = NSScreen.main else { return }
        let anchor = anchor()
        var precedingHeights: [CGFloat] = []
        for entry in entries {
            let origin = anchor.origin(
                forPanelOfSize: entry.panel.frame.size,
                stackedAfter: precedingHeights,
                in: screen.visibleFrame,
                spacing: Self.spacing
            )
            entry.panel.setFrameOrigin(origin)
            precedingHeights.append(entry.panel.frame.size.height)
        }
    }
}
