import Foundation

/// Turns usage history into a bounded boost.
///
/// Every weight is a plain constant and the tests assert their *ordering*, so
/// these can be tuned without rewriting the suite. `now` is a parameter rather
/// than `Date()` so decay is testable without waiting a fortnight.
enum FrecencyScoring {
    /// The most usage can ever add. The text gate already dropped non-matches;
    /// this bound is what stops usage from swamping relevance among the rest.
    static let maximumBoost: Double = 0.5

    private enum Weight {
        /// A selection made through this exact query.
        static let sameQuery: Double = 0.30
        /// A selection of this result through some other query.
        static let anyQuery: Double = 0.12
        /// The most repetition alone can contribute.
        static let frequency: Double = 0.15
    }

    /// How long until a selection counts for half as much.
    private static let halfLife: TimeInterval = 14 * 86_400

    /// Where repetition stops helping. Small on purpose: the first handful of
    /// selections carries almost all of the weight, and past roughly twenty the
    /// curve is flat enough that a thousand selections and a hundred are worth
    /// the same. That flatness is what `frequencySaturates` pins.
    private static let frequencySaturation = 5.0

    static func boost(
        for resultID: String,
        query: NormalizedQuery,
        usage: UsageSnapshot,
        now: Date
    ) -> Double {
        let entries = usage.entries(forResultID: resultID)
        guard !entries.isEmpty else { return 0 }

        var total = 0.0
        for entry in entries {
            let recency = decay(from: entry.lastSelected, to: now)
            let association = entry.query == query.folded ? Weight.sameQuery : Weight.anyQuery
            total += association * recency
            total += Weight.frequency * saturating(entry.selectionCount) * recency
        }
        return min(total, maximumBoost)
    }

    /// Exponential decay on a half-life, so something used today counts fully
    /// and something used a year ago counts for almost nothing.
    private static func decay(from date: Date, to now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(date))
        return pow(0.5, elapsed / halfLife)
    }

    /// Approaches 1 as the count grows, so repetition helps and then stops.
    private static func saturating(_ count: Int) -> Double {
        let count = Double(max(0, count))
        return count / (count + frequencySaturation)
    }
}
