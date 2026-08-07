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
    }

    private static let spacing: CGFloat = 10

    private var entries: [Entry] = []
    private let anchor: () -> HUDAnchor

    init(anchor: @escaping () -> HUDAnchor = { Preferences.shared.hudAnchor }) {
        self.anchor = anchor
    }

    var visibleCount: Int { entries.count }

    /// The frames, newest first — what the layout tests read.
    var frames: [CGRect] { entries.map(\.panel.frame) }

    func show(_ presentation: HUDPresentation) {
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: .zero))
        panel.contentView = NSHostingView(
            rootView: HUDView(presentation: presentation) { [presentation] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(presentation.body, forType: .string)
            }
        )
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)

        var entry = Entry(panel: panel, expiry: nil)
        entry.expiry = Task { [weak self] in
            try? await Task.sleep(for: presentation.duration)
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
        entries.insert(entry, at: 0)
        panel.orderFrontRegardless()
        layout()
    }

    func dismissAll() {
        for entry in entries {
            entry.expiry?.cancel()
            entry.panel.orderOut(nil)
        }
        entries.removeAll()
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
