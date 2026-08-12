import Foundation

/// Where HUDs appear, and how a stack of them grows.
///
/// Six positions, as PRD §11 lists them. The stack always grows away from the
/// anchored edge, so the newest panel is the one nearest that edge and the
/// older ones drift toward the middle of the screen.
enum HUDAnchor: String, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight

    /// The distance from the screen's edges, matching the launcher's own
    /// breathing room.
    private static let margin: CGFloat = 20

    var isTop: Bool {
        switch self {
        case .topLeft, .topCenter, .topRight: true
        case .bottomLeft, .bottomCenter, .bottomRight: false
        }
    }

    /// One panel waiting to be placed: how big it is, and the usable area of
    /// the display it belongs on.
    struct Panel: Equatable {
        let size: CGSize
        let visibleFrame: CGRect
    }

    /// Where every panel in a stack goes, in the order they are given —
    /// newest first, as `HUDController` keeps them.
    ///
    /// Each panel carries its own display, because a HUD belongs on the screen
    /// its run was started from and two runs can come from two screens. Panels
    /// stack against the others on their own display and ignore the rest: a
    /// HUD on the second monitor should not be pushed down the screen by one
    /// on the first.
    func origins(for panels: [Panel], spacing: CGFloat) -> [CGPoint] {
        // What each display already holds, found by scanning rather than by
        // dictionary: `CGRect` is not `Hashable`, and a Mac has one or two
        // screens, where a scan costs nothing.
        var placed: [(visibleFrame: CGRect, heights: [CGFloat])] = []
        return panels.map { panel in
            let display = placed.firstIndex { $0.visibleFrame == panel.visibleFrame } ?? placed.count
            if display == placed.count { placed.append((panel.visibleFrame, [])) }
            let origin = origin(
                forPanelOfSize: panel.size,
                stackedAfter: placed[display].heights,
                in: panel.visibleFrame,
                spacing: spacing
            )
            placed[display].heights.append(panel.size.height)
            return Self.clamped(origin, ofPanelOfSize: panel.size, to: panel.visibleFrame)
        }
    }

    /// Keeps a panel inside the screen. A stack tall enough to pass the far
    /// edge would otherwise keep walking off it, one panel at a time, and the
    /// oldest HUDs would be drawn where nobody can read them.
    ///
    /// The `max` in each bound is for a panel taller or wider than the screen
    /// itself: pinning it to the low edge shows its beginning, which is the
    /// part worth reading.
    private static func clamped(
        _ origin: CGPoint, ofPanelOfSize size: CGSize, to visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, visibleFrame.minX),
                max(visibleFrame.maxX - size.width, visibleFrame.minX)
            ),
            y: min(
                max(origin.y, visibleFrame.minY),
                max(visibleFrame.maxY - size.height, visibleFrame.minY)
            )
        )
    }

    /// `precedingHeights` are the actual heights of the panels already placed
    /// closer to the anchored edge, in any order — only their sum matters. An
    /// index cannot stand in for this: HUDs vary in height with how much a
    /// plugin printed, so a stack only clears each panel it passes by summing
    /// what that panel actually measured, not by multiplying a uniform guess.
    func origin(
        forPanelOfSize size: CGSize,
        stackedAfter precedingHeights: [CGFloat],
        in visibleFrame: CGRect,
        spacing: CGFloat
    ) -> CGPoint {
        let offset = precedingHeights.reduce(CGFloat.zero) { $0 + $1 + spacing }
        let x: CGFloat = switch self {
        case .topLeft, .bottomLeft:
            visibleFrame.minX + Self.margin
        case .topCenter, .bottomCenter:
            visibleFrame.minX + (visibleFrame.width - size.width) / 2
        case .topRight, .bottomRight:
            visibleFrame.maxX - size.width - Self.margin
        }
        let y: CGFloat = isTop
            ? visibleFrame.maxY - size.height - Self.margin - offset
            : visibleFrame.minY + Self.margin + offset
        return CGPoint(x: x, y: y)
    }
}
