import Testing
import Foundation
@testable import Pium

@Suite("HUD anchor")
@MainActor
struct HUDAnchorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let panel = CGSize(width: 300, height: 100)

    @Test func thetopRightAnchorSitsUnderTheTopEdge() {
        let origin = HUDAnchor.topRight.origin(
            forPanelOfSize: panel, atIndex: 0, in: screen, spacing: 10
        )
        #expect(origin.x == 1000 - 300 - 20)
        #expect(origin.y == 800 - 100 - 20)
    }

    /// The second panel goes below the first at a top anchor, and above it at a
    /// bottom one — always away from the edge it is anchored to.
    @Test func thesecondPanelStacksAwayFromItsEdge() {
        let first = HUDAnchor.topRight.origin(
            forPanelOfSize: panel, atIndex: 0, in: screen, spacing: 10
        )
        let second = HUDAnchor.topRight.origin(
            forPanelOfSize: panel, atIndex: 1, in: screen, spacing: 10
        )
        #expect(second.y == first.y - 110)

        let bottomFirst = HUDAnchor.bottomLeft.origin(
            forPanelOfSize: panel, atIndex: 0, in: screen, spacing: 10
        )
        let bottomSecond = HUDAnchor.bottomLeft.origin(
            forPanelOfSize: panel, atIndex: 1, in: screen, spacing: 10
        )
        #expect(bottomSecond.y == bottomFirst.y + 110)
    }

    @Test func acenterAnchorCentersHorizontally() {
        let origin = HUDAnchor.topCenter.origin(
            forPanelOfSize: panel, atIndex: 0, in: screen, spacing: 10
        )
        #expect(origin.x == (1000 - 300) / 2)
    }

    /// A screen whose frame does not start at zero — a second display — must
    /// place relative to that frame, not to the origin.
    @Test func placementFollowsTheScreenItIsGiven() {
        let secondary = CGRect(x: 1000, y: -200, width: 800, height: 600)
        let origin = HUDAnchor.bottomLeft.origin(
            forPanelOfSize: panel, atIndex: 0, in: secondary, spacing: 10
        )
        #expect(origin.x == 1020)
        #expect(origin.y == -180)
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
