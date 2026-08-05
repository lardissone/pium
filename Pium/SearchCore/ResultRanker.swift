import Foundation

/// The final ordering across every provider.
///
/// Pure by design: results in, results out, with the clock and the usage
/// history passed as arguments. That is what lets the tie-break, the boost, and
/// the quota be tested as plain data.
enum ResultRanker {
    /// The rows a user sees without scrolling. The quota applies here only.
    static let leadingWindow = 10

    /// Initial tuning per the PRD: at most six files in the first ten results.
    /// An internal, test-adjusted value rather than a public contract.
    static let maximumFilesInLeadingWindow = 6

    static func rank(
        _ results: [SearchResult],
        for query: NormalizedQuery,
        usage: UsageSnapshot,
        now: Date
    ) -> [SearchResult] {
        let scored = results.map { result in
            (
                result: result,
                score: result.textScore + FrecencyScoring.boost(
                    for: result.id, query: query, usage: usage, now: now
                )
            )
        }

        let ordered = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.result.kind.tieBreakRank < rhs.result.kind.tieBreakRank
        }.map(\.result)

        return applyingFileQuota(to: ordered)
    }

    /// Moves files beyond the quota out of the leading window, preserving their
    /// relative order. They are demoted, never dropped: the list stays
    /// scrollable to every match.
    ///
    /// The quota can only hold files back as far as there is other content to
    /// fill the window with. Twenty files and one application still put nine
    /// files on the first screen — what the quota guarantees there is that the
    /// application is on it at all.
    private static func applyingFileQuota(to results: [SearchResult]) -> [SearchResult] {
        guard results.count > leadingWindow else { return results }

        var leading: [SearchResult] = []
        var demoted: [SearchResult] = []
        var rest: [SearchResult] = []
        var filesInLeadingWindow = 0

        for result in results {
            guard leading.count < leadingWindow else {
                rest.append(result)
                continue
            }
            if result.kind == .file {
                if filesInLeadingWindow < maximumFilesInLeadingWindow {
                    filesInLeadingWindow += 1
                    leading.append(result)
                } else {
                    demoted.append(result)
                }
            } else {
                leading.append(result)
            }
        }

        return leading + demoted + rest
    }
}
