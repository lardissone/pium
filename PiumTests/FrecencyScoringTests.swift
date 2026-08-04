import Testing
import Foundation
@testable import Pium

@Suite("Frecency scoring")
struct FrecencyScoringTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func usage(_ entries: [(String, String, Int, TimeInterval)]) -> UsageSnapshot {
        UsageSnapshot(entries: entries.map { resultID, query, count, agoDays in
            FrecencyEntry(
                resultID: resultID,
                query: query,
                selectionCount: count,
                lastSelected: now.addingTimeInterval(-agoDays * 86_400)
            )
        })
    }

    private func boost(
        _ resultID: String,
        _ query: String,
        _ usage: UsageSnapshot
    ) -> Double {
        FrecencyScoring.boost(
            for: resultID,
            query: TextNormalizer.query(query),
            usage: usage,
            now: now
        )
    }

    @Test func somethingNeverSelectedGetsNothing() {
        #expect(boost("safari", "saf", usage([])) == 0)
    }

    /// The whole point: what you picked before for this query comes back first.
    @Test func aPriorSelectionRaisesTheResult() {
        #expect(boost("safari", "saf", usage([("safari", "saf", 1, 0)])) > 0)
    }

    /// The PRD calls for a stronger boost when the same query led here before.
    @Test func theSameQueryBeatsADifferentOne() {
        let sameQuery = boost("safari", "saf", usage([("safari", "saf", 1, 0)]))
        let otherQuery = boost("safari", "saf", usage([("safari", "browser", 1, 0)]))
        #expect(sameQuery > otherQuery)
        #expect(otherQuery > 0)
    }

    @Test func moreSelectionsBeatFewer() {
        let many = boost("safari", "saf", usage([("safari", "saf", 20, 0)]))
        let few = boost("safari", "saf", usage([("safari", "saf", 1, 0)]))
        #expect(many > few)
    }

    /// Frequency saturates, or one obsessively used result would outrank
    /// everything for the rest of time.
    @Test func frequencySaturates() {
        let hundred = boost("safari", "saf", usage([("safari", "saf", 100, 0)]))
        let thousand = boost("safari", "saf", usage([("safari", "saf", 1000, 0)]))
        #expect(thousand - hundred < 0.01)
    }

    @Test func recentBeatsStale() {
        let today = boost("safari", "saf", usage([("safari", "saf", 3, 0)]))
        let lastYear = boost("safari", "saf", usage([("safari", "saf", 3, 365)]))
        #expect(today > lastYear)
    }

    /// The bound is the PRD's guarantee that usage reorders matches without
    /// resurrecting non-matches. Nothing may exceed it, however heavy.
    @Test func theBoostIsBounded() {
        let extreme = boost("safari", "saf", usage([
            ("safari", "saf", 100_000, 0),
            ("safari", "sa", 100_000, 0),
            ("safari", "s", 100_000, 0),
        ]))
        #expect(extreme <= FrecencyScoring.maximumBoost)
    }

    /// A bounded boost added to a score above the gate can never drop below it,
    /// which is what the ranker relies on.
    @Test func theBoostIsNeverNegative() {
        #expect(boost("safari", "saf", usage([("safari", "saf", 1, 10_000)])) >= 0)
    }
}
