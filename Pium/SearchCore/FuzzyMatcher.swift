import Foundation

/// Scores how well a query matches a candidate, in `0...1`.
///
/// The tiers come straight from the PRD's stated priority order. Weights are
/// deliberately plain constants: the tests assert their *ordering*, so they can
/// be tuned without rewriting the suite.
enum FuzzyMatcher {
    /// At or below this, a candidate is not a match and is dropped before any
    /// usage data is considered. This is the text gate the PRD requires.
    static let rejectionThreshold: Double = 0.1

    private enum Tier {
        static let exact: Double = 1.0
        static let prefix: Double = 0.8
        static let wholeWord: Double = 0.6
        static let acronym: Double = 0.45
        static let subsequence: Double = 0.3
    }

    static func score(
        _ query: NormalizedQuery,
        against candidate: NormalizedCandidate
    ) -> Double {
        guard !query.isEmpty else { return 0 }
        let needle = query.folded

        if candidate.folded == needle { return Tier.exact }
        if candidate.folded.hasPrefix(needle) {
            return Tier.prefix * lengthRatio(needle, candidate.folded)
        }
        if candidate.tokens.contains(needle) { return Tier.wholeWord }
        if candidate.tokens.contains(where: { $0.hasPrefix(needle) }) {
            return Tier.wholeWord * 0.9
        }
        if candidate.acronym == needle { return Tier.acronym }
        if isOrderedSubsequence(needle, of: candidate.folded) {
            return Tier.subsequence * lengthRatio(needle, candidate.folded)
        }
        return 0
    }

    /// The strongest score across a candidate's terms — title, aliases,
    /// keywords — since matching any one of them is a match.
    static func bestScore(
        _ query: NormalizedQuery,
        againstAnyOf candidates: [NormalizedCandidate]
    ) -> Double {
        candidates.reduce(0) { max($0, score(query, against: $1)) }
    }

    /// Rewards candidates the query covers more of, so "Mail" beats "MailMate"
    /// for "mail". Never returns zero for a real match.
    private static func lengthRatio(_ needle: String, _ haystack: String) -> Double {
        guard !haystack.isEmpty else { return 0 }
        let ratio = Double(needle.count) / Double(haystack.count)
        // Compress into 0.75...1.0 so length nudges the score without letting a
        // long candidate fall below a weaker tier.
        return 0.75 + 0.25 * ratio
    }

    /// Whether every character of `needle` appears in `haystack` in order.
    private static func isOrderedSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = Substring(haystack)
        for character in needle {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}
