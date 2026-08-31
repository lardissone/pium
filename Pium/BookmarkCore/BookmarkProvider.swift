import AppKit

/// Turns the user's bookmarks into search results.
///
/// Bookmarks answer from memory and from the first character, so there is one
/// batch and it is ready now — the same shape as `PluginProvider`.
@MainActor
final class BookmarkProvider: ResultProvider {
    nonisolated let kind = ResultKind.bookmark

    private let store: BookmarkStore
    private let open: @Sendable @MainActor (Bookmark, String) -> Void
    private let copy: @Sendable @MainActor (String) -> Void

    init(
        store: BookmarkStore,
        open: @escaping @Sendable @MainActor (Bookmark, String) -> Void,
        copy: @escaping @Sendable @MainActor (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.store = store
        self.open = open
        self.copy = copy
    }

    func results(for query: NormalizedQuery) -> AsyncStream<[SearchResult]> {
        AsyncStream { continuation in
            continuation.yield(matches(for: query))
            continuation.finish()
        }
    }

    private func matches(for query: NormalizedQuery) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        return store.bookmarks
            .compactMap { bookmark -> SearchResult? in
                let score = FuzzyMatcher.bestScore(
                    query,
                    againstAnyOf: terms(of: bookmark).map(TextNormalizer.candidate)
                )
                // The same hard text gate the other providers apply. It matters
                // more here than anywhere: a bookmark outranks everything on an
                // equal score, so one that should not be in the list at all
                // would be in the list first.
                guard score > FuzzyMatcher.rejectionThreshold else { return nil }
                return result(for: bookmark, score: score)
            }
            .sorted { $0.textScore > $1.textScore }
    }

    private func terms(of bookmark: Bookmark) -> [String] {
        [bookmark.name] + bookmark.keywords
    }

    private func result(for bookmark: Bookmark, score: Double) -> SearchResult {
        let openAction = ResultAction(
            id: "open",
            title: String(localized: "action.open"),
            shortcut: .returnKey
        ) { [open] input in open(bookmark, input) }

        // Copies what would actually be opened, argument and all, rather than
        // the template — the text with `{{input}}` still in it is of no use to
        // anybody it is pasted to.
        let copyAction = ResultAction(
            id: "copy",
            title: String(localized: "action.copyDestination"),
            shortcut: .commandReturn
        ) { [copy] input in
            guard let resolved = bookmark.destination.resolved(input: input) else { return }
            copy(resolved)
        }

        return SearchResult(
            id: bookmark.id.uuidString,
            kind: .bookmark,
            title: bookmark.name,
            subtitle: bookmark.destination.template,
            iconSource: BookmarkIcon.source(for: bookmark),
            searchableTerms: terms(of: bookmark),
            textScore: score,
            actions: [openAction, copyAction],
            argument: bookmark.destination.takesArgument
                ? ArgumentRequest(placeholder: nil, isRequired: true)
                : nil
        )
    }
}
