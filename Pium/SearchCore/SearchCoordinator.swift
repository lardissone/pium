import Foundation

/// Runs a query across every provider and merges the results.
///
/// Each search takes a generation number. When a newer search starts, older
/// ones return nothing rather than overwriting fresher results — the behaviour
/// that keeps the list sane while the user types quickly.
@MainActor
final class SearchCoordinator {
    private let providers: [any ResultProvider]
    private(set) var currentGeneration = 0

    init(providers: [any ResultProvider]) {
        self.providers = providers
    }

    func search(_ text: String) async -> [SearchResult] {
        currentGeneration += 1
        let generation = currentGeneration

        let query = TextNormalizer.query(text)
        // No results, recent items, or favourites for an empty query.
        guard !query.isEmpty else { return [] }

        let signpost = Signposts.search.beginInterval("query")
        var merged: [SearchResult] = []
        await withTaskGroup(of: [SearchResult].self) { group in
            for provider in providers {
                group.addTask { await provider.results(for: query) }
            }
            for await batch in group { merged += batch }
        }
        Signposts.search.endInterval("query", signpost)

        // A newer query started while this one was running.
        guard generation == currentGeneration else { return [] }

        return merged.sorted { lhs, rhs in
            if lhs.textScore != rhs.textScore { return lhs.textScore > rhs.textScore }
            return lhs.kind.tieBreakRank < rhs.kind.tieBreakRank
        }
    }
}
