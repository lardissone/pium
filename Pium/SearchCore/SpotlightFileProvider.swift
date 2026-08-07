import AppKit

/// Turns Spotlight matches into file results.
///
/// The enabled flag and the scope arrive as closures rather than being read
/// from `Preferences.shared`, so a change in Settings is picked up without
/// rebuilding the provider, and a test can vary them freely.
@MainActor
final class SpotlightFileProvider: ResultProvider {
    nonisolated let kind = ResultKind.file


    /// Long enough that a burst of typing issues one query, short enough that
    /// results do not feel late. Tunable per the PRD.
    static let defaultDebounce = Duration.milliseconds(150)

    private let search: any MetadataSearching
    private let isEnabled: @Sendable @MainActor () -> Bool
    private let scope: @Sendable @MainActor () -> FileSearchScope
    private let debounce: Duration
    private let open: @Sendable @MainActor (URL) -> Void
    private let reveal: @Sendable @MainActor (URL) -> Void

    init(
        search: any MetadataSearching = SpotlightMetadataSearch(),
        isEnabled: @escaping @Sendable @MainActor () -> Bool = {
            Preferences.shared.isFileSearchEnabled
        },
        scope: @escaping @Sendable @MainActor () -> FileSearchScope = {
            Preferences.shared.fileSearchScope
        },
        debounce: Duration = SpotlightFileProvider.defaultDebounce,
        open: @escaping @Sendable @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        },
        reveal: @escaping @Sendable @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    ) {
        self.search = search
        self.isEnabled = isEnabled
        self.scope = scope
        self.debounce = debounce
        self.open = open
        self.reveal = reveal
    }

    func results(for query: NormalizedQuery) -> AsyncStream<[SearchResult]> {
        let (results, report) = AsyncStream<[SearchResult]>.makeStream()

        // Checked before anything else: turning file search off must stop the
        // query being issued, not discard its results afterwards.
        guard
            isEnabled(),
            query.folded.count >= SpotlightQuery.minimumQueryLength
        else {
            report.finish()
            return results
        }

        let task = Task {
            // Only Spotlight waits for typing to settle; applications and
            // plugins answer from the first character.
            if debounce > .zero { try? await Task.sleep(for: debounce) }
            guard !Task.isCancelled else {
                report.finish()
                return
            }

            let signpost = Signposts.search.beginInterval("files")
            let urls = search.search(
                predicate: SpotlightQuery.predicate(for: query),
                scope: scope()
            )
            for await batch in urls {
                guard !Task.isCancelled else { break }
                report.yield(self.results(from: batch, query: query))
            }
            Signposts.search.endInterval("files", signpost)
            report.finish()
        }

        report.onTermination = { _ in task.cancel() }
        return results
    }

    private func results(from urls: [URL], query: NormalizedQuery) -> [SearchResult] {
        urls
            .filter(SpotlightQuery.isPresentable)
            .compactMap { url in
                let name = url.lastPathComponent
                let score = FuzzyMatcher.bestScore(
                    query,
                    againstAnyOf: [TextNormalizer.candidate(name)]
                )
                // The same hard text gate the other providers apply.
                guard score > FuzzyMatcher.rejectionThreshold else { return nil }
                return result(for: url, name: name, score: score)
            }
            .sorted { $0.textScore > $1.textScore }
    }

    private func result(for url: URL, name: String, score: Double) -> SearchResult {
        SearchResult(
            id: url.path,
            kind: .file,
            title: name,
            subtitle: SpotlightQuery.subtitle(for: url),
            // Resolved with `NSWorkspace.icon(forFile:)`, which returns the
            // right icon for any file, not only for a bundle.
            iconSource: .applicationBundle(url),
            searchableTerms: [name],
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
