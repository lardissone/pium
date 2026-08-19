import AppKit

/// Turns the application index into ranked search results.
///
/// `open` and `reveal` are injected so the provider's behaviour is testable
/// without launching anything.
@MainActor
final class ApplicationProvider: ResultProvider {
    nonisolated let kind = ResultKind.application

    private let index: ApplicationIndex
    private let open: @Sendable @MainActor (URL) -> Void
    private let reveal: @Sendable @MainActor (URL) -> Void

    init(
        index: ApplicationIndex,
        open: @escaping @Sendable @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        },
        reveal: @escaping @Sendable @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    ) {
        self.index = index
        self.open = open
        self.reveal = reveal
    }

    func results(for query: NormalizedQuery) -> AsyncStream<[SearchResult]> {
        // The index is in memory, so there is one batch and it is ready now.
        AsyncStream { continuation in
            continuation.yield(matches(for: query))
            continuation.finish()
        }
    }

    private func matches(for query: NormalizedQuery) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        return index.applications
            .compactMap { application in
                let score = FuzzyMatcher.bestScore(
                    query,
                    againstAnyOf: [TextNormalizer.candidate(application.name)]
                )
                // The hard text gate: below this the application is not a match
                // at all, and no later ranking may resurrect it.
                guard score > FuzzyMatcher.rejectionThreshold else { return nil }
                return result(for: application, score: score)
            }
            .sorted { $0.textScore > $1.textScore }
    }

    private func result(
        for application: InstalledApplication,
        score: Double
    ) -> SearchResult {
        let url = application.bundleURL
        return SearchResult(
            id: application.id,
            kind: .application,
            title: application.name,
            subtitle: nil,
            iconSource: .fileIcon(url),
            searchableTerms: [application.name],
            textScore: score,
            actions: [
                ResultAction(
                    id: "open",
                    title: String(localized: "action.open"),
                    shortcut: .returnKey
                ) { [open] _ in open(url) },
                ResultAction(
                    id: "reveal",
                    title: String(localized: "action.revealInFinder"),
                    shortcut: .commandReturn
                ) { [reveal] _ in reveal(url) },
            ]
        )
    }
}
