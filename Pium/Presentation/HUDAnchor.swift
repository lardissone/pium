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
