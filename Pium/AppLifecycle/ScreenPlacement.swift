import Foundation

/// Where the launcher panel appears.
///
/// These are pure functions over rectangles rather than methods on `NSScreen`,
/// so multi-display behaviour is testable without real hardware. The thin
/// adapter that reads live `NSScreen` state lives in `LauncherPanelController`.
enum ScreenPlacement {
    /// Fraction of the usable height, measured down from the top, at which the
    /// panel's vertical centre sits.
    static let verticalAnchor: CGFloat = 1.0 / 3.0

    /// Bottom-left origin in AppKit coordinates for a panel of `panelSize` on a
    /// display whose usable area is `visibleFrame`.
    ///
    /// Horizontally centred, anchored near the upper third, and clamped so the
    /// panel stays entirely on the display.
    static func origin(panelSize: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let centredX = visibleFrame.midX - panelSize.width / 2
        let anchorY = visibleFrame.maxY - visibleFrame.height * verticalAnchor
        let bottomY = anchorY - panelSize.height / 2

        return CGPoint(
            x: clamp(
                centredX,
                lower: visibleFrame.minX,
                upper: visibleFrame.maxX - panelSize.width
            ),
            y: clamp(
                bottomY,
                lower: visibleFrame.minY,
                upper: visibleFrame.maxY - panelSize.height
            )
        )
    }

    /// Index into `frames` of the display that should host the launcher.
    ///
    /// `mainIndex` is the display holding the window with keyboard focus. When
    /// that is unknown, the pointer's display is used; failing that, the first
    /// display. Returns `nil` only when there are no displays at all.
    static func indexOfTargetScreen(
        mainIndex: Int?,
        mouseLocation: CGPoint,
        frames: [CGRect]
    ) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let mainIndex, frames.indices.contains(mainIndex) { return mainIndex }
        if let pointerIndex = frames.firstIndex(where: { $0.contains(mouseLocation) }) {
            return pointerIndex
        }
        return frames.startIndex
    }

    /// Keeps `value` within the range, pinning to `lower` when the range is
    /// empty because the panel is larger than the display.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return lower }
        return min(max(value, lower), upper)
    }
}
