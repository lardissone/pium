import Testing
import Foundation
@testable import Pium

/// Expected coordinates are `CGFloat`-typed constants. Integer arithmetic
/// written inline in an `#expect` type-checks as `Int` — the macro passes each
/// side to a separate generic parameter, so the literals never see the
/// `CGFloat` they are compared against — and an `Int` never equals a `CGFloat`.
@Suite("HUD anchor")
@MainActor
struct HUDAnchorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let panel = CGSize(width: 300, height: 100)

    @Test func thetopRightAnchorSitsUnderTheTopEdge() {
        let origin = HUDAnchor.topRight.origin(
            forPanelOfSize: panel, stackedAfter: [], in: screen, spacing: 10
        )
        let expectedX: CGFloat = 1000 - 300 - 20
        let expectedY: CGFloat = 800 - 100 - 20
        #expect(origin.x == expectedX)
        #expect(origin.y == expectedY)
    }

    /// The second panel goes below the first at a top anchor, and above it at a
    /// bottom one — always away from the edge it is anchored to.
    @Test func thesecondPanelStacksAwayFromItsEdge() {
        let first = HUDAnchor.topRight.origin(
            forPanelOfSize: panel, stackedAfter: [], in: screen, spacing: 10
        )
        let second = HUDAnchor.topRight.origin(
            forPanelOfSize: panel, stackedAfter: [panel.height], in: screen, spacing: 10
        )
        #expect(second.y == first.y - 110)

        let bottomFirst = HUDAnchor.bottomLeft.origin(
            forPanelOfSize: panel, stackedAfter: [], in: screen, spacing: 10
        )
        let bottomSecond = HUDAnchor.bottomLeft.origin(
            forPanelOfSize: panel, stackedAfter: [panel.height], in: screen, spacing: 10
        )
        #expect(bottomSecond.y == bottomFirst.y + 110)
    }

    /// The bug this guards against: placing the second panel `size.height`
    /// (its own height) away from the edge rather than the *first* panel's
    /// height would let a short panel tuck under a tall one instead of below
    /// it. Real HUDs are not uniform — `HUDView` grows with how much a plugin
    /// printed — so a fixed per-slot offset is wrong the moment two panels
    /// differ.
    @Test func adifferentlySizedPrecedingPanelDoesNotOverlap() {
        let tall = CGSize(width: 300, height: 220)
        let short = CGSize(width: 300, height: 60)
        let first = HUDAnchor.topRight.origin(
            forPanelOfSize: tall, stackedAfter: [], in: screen, spacing: 10
        )
        let second = HUDAnchor.topRight.origin(
            forPanelOfSize: short, stackedAfter: [tall.height], in: screen, spacing: 10
        )
        // The first panel occupies [first.y, first.y + tall.height]. The
        // second must sit entirely below that, with at least one spacing gap.
        #expect(second.y + short.height <= first.y)
    }

    @Test func acenterAnchorCentersHorizontally() {
        let origin = HUDAnchor.topCenter.origin(
            forPanelOfSize: panel, stackedAfter: [], in: screen, spacing: 10
        )
        let expectedX: CGFloat = (1000 - 300) / 2
        #expect(origin.x == expectedX)
    }

    /// A screen whose frame does not start at zero — a second display — must
    /// place relative to that frame, not to the origin.
    @Test func placementFollowsTheScreenItIsGiven() {
        let secondary = CGRect(x: 1000, y: -200, width: 800, height: 600)
        let origin = HUDAnchor.bottomLeft.origin(
            forPanelOfSize: panel, stackedAfter: [], in: secondary, spacing: 10
        )
        #expect(origin.x == 1020)
        #expect(origin.y == -180)
    }

    /// A HUD belongs on the display its run started from, so a stack can span
    /// two of them — and each display has to stack on its own. Sharing one
    /// running offset would push the second monitor's only HUD down the screen
    /// to clear a panel it cannot collide with.
    @Test func eachDisplayStacksIndependently() {
        let secondary = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let origins = HUDAnchor.topRight.origins(
            for: [
                HUDAnchor.Panel(size: panel, visibleFrame: screen),
                HUDAnchor.Panel(size: panel, visibleFrame: secondary),
                HUDAnchor.Panel(size: panel, visibleFrame: screen),
            ],
            spacing: 10
        )
        let topOfPrimary: CGFloat = 800 - 100 - 20
        let topOfSecondary: CGFloat = 600 - 100 - 20
        #expect(origins[0].y == topOfPrimary)
        // Alone on its display, however many panels are on the other one.
        #expect(origins[1].y == topOfSecondary)
        #expect(origins[2].y == topOfPrimary - 110)
    }

    /// A stack taller than the screen would otherwise keep walking past the
    /// far edge, one panel at a time, and the oldest HUDs would be drawn where
    /// nobody can read them.
    @Test func astackTallerThanTheScreenStopsAtItsEdge() {
        let short = CGRect(x: 0, y: 0, width: 1000, height: 300)
        let origins = HUDAnchor.topRight.origins(
            for: Array(repeating: HUDAnchor.Panel(size: panel, visibleFrame: short), count: 5),
            spacing: 10
        )
        #expect(origins.allSatisfy { $0.y >= short.minY })
        #expect(origins.allSatisfy { $0.y + panel.height <= short.maxY })
    }

    /// A panel bigger than the screen it is on shows its beginning rather than
    /// its middle: the top edge is the part worth reading.
    @Test func apanelTallerThanItsScreenIsPinnedToTheLowEdge() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 80)
        let origins = HUDAnchor.topRight.origins(
            for: [HUDAnchor.Panel(size: panel, visibleFrame: tiny)], spacing: 10
        )
        #expect(origins[0].x == tiny.minX)
        #expect(origins[0].y == tiny.minY)
    }

    @Test func thedefaultAnchorIsTopRight() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(preferences.hudAnchor == .topRight)
    }

    @Test func theanchorRoundTripsThroughPreferences() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.hudAnchor = .bottomCenter
        #expect(preferences.hudAnchor == .bottomCenter)
    }
}
