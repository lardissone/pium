import Testing
import Foundation
@testable import Pium

@Suite("ScreenPlacement")
struct ScreenPlacementTests {
    /// A 1512×982 usable area, the shape of a 14" MacBook Pro minus the menubar.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let panel = CGSize(width: 680, height: 56)

    @Test func panelIsHorizontallyCentred() {
        let origin = ScreenPlacement.origin(panelSize: panel, in: laptop)
        #expect(origin.x == laptop.midX - panel.width / 2)
    }

    /// AppKit's y axis grows upward, so "upper third" is measured down from
    /// `maxY`. The panel's vertical centre sits on that line.
    @Test func panelCentreSitsOnTheUpperThirdLine() {
        let origin = ScreenPlacement.origin(panelSize: panel, in: laptop)
        let centreY = origin.y + panel.height / 2
        let expected = laptop.maxY - laptop.height * ScreenPlacement.verticalAnchor
        #expect(abs(centreY - expected) < 0.001)
    }

    /// A secondary display to the left of the primary has a negative origin.
    /// The panel must land on that display, not at x ≈ 0.
    @Test func placementRespectsANegativeDisplayOrigin() {
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = ScreenPlacement.origin(panelSize: panel, in: secondary)
        #expect(origin.x < 0)
        #expect(origin.x >= secondary.minX)
        #expect(origin.x + panel.width <= secondary.maxX)
    }

    /// The panel never hangs off the display, even when it is larger than the
    /// usable area.
    @Test func oversizedPanelIsPinnedInsideTheDisplay() {
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 40)
        let origin = ScreenPlacement.origin(panelSize: panel, in: tiny)
        #expect(origin.x == tiny.minX)
        #expect(origin.y == tiny.minY)
    }

    @Test func targetScreenPrefersTheFocusedDisplay() {
        let frames = [laptop, CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        let index = ScreenPlacement.indexOfTargetScreen(
            mainIndex: 1,
            mouseLocation: CGPoint(x: 100, y: 100),
            frames: frames
        )
        #expect(index == 1)
    }

    /// With no focused window, the pointer's display is the fallback.
    @Test func targetScreenFallsBackToThePointer() {
        let frames = [laptop, CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        let index = ScreenPlacement.indexOfTargetScreen(
            mainIndex: nil,
            mouseLocation: CGPoint(x: 2000, y: 400),
            frames: frames
        )
        #expect(index == 1)
    }

    /// With neither signal usable, the first display is the last resort.
    @Test func targetScreenFallsBackToTheFirstDisplay() {
        let index = ScreenPlacement.indexOfTargetScreen(
            mainIndex: nil,
            mouseLocation: CGPoint(x: 99_999, y: 99_999),
            frames: [laptop]
        )
        #expect(index == 0)
    }

    @Test func targetScreenIsNilWhenThereAreNoDisplays() {
        let index = ScreenPlacement.indexOfTargetScreen(
            mainIndex: nil,
            mouseLocation: .zero,
            frames: []
        )
        #expect(index == nil)
    }

    /// A stale index from a display that was just unplugged must not crash.
    @Test func targetScreenIgnoresAnOutOfRangeMainIndex() {
        let index = ScreenPlacement.indexOfTargetScreen(
            mainIndex: 7,
            mouseLocation: CGPoint(x: 100, y: 100),
            frames: [laptop]
        )
        #expect(index == 0)
    }
}
