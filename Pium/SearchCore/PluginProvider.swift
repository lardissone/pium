import AppKit

/// Turns the plugin index into search results.
///
/// Plugins answer from memory and from the first character, sharing the 50 ms
/// budget with applications, so there is one batch and it is ready now.
@MainActor
final class PluginProvider: ResultProvider {
    nonisolated let kind = ResultKind.plugin

    /// Shown when a manifest names no icon, or names one macOS does not have.
    static let fallbackSymbol = "terminal"

    private let index: PluginIndex
    private let reveal: @Sendable @MainActor (URL) -> Void

    init(
        index: PluginIndex,
        reveal: @escaping @Sendable @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    ) {
        self.index = index
        self.reveal = reveal
    }

    func results(for query: NormalizedQuery) -> AsyncStream<[SearchResult]> {
        AsyncStream { continuation in
            continuation.yield(matches(for: query))
            continuation.finish()
        }
    }

    private func matches(for query: NormalizedQuery) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        return index.records
            .compactMap { record in
                let score = FuzzyMatcher.bestScore(
                    query,
                    againstAnyOf: terms(of: record).map(TextNormalizer.candidate)
                )
                // The same hard text gate the other providers apply.
                guard score > FuzzyMatcher.rejectionThreshold else { return nil }
                return result(for: record, score: score)
            }
            .sorted { $0.textScore > $1.textScore }
    }

    /// What a query may match. An invalid file has no manifest, so it is found
    /// by its filename — the only name its author knows it by.
    private func terms(of record: PluginRecord) -> [String] {
        guard let manifest = record.manifest else {
            return [record.fileURL.lastPathComponent]
        }
        return [manifest.name] + manifest.aliases + manifest.keywords
    }

    private func result(for record: PluginRecord, score: Double) -> SearchResult {
        let url = record.fileURL
        let revealAction = ResultAction(
            id: "reveal",
            title: String(localized: "action.revealJSON"),
            // The primary action, because executing is Phase 5 and a row whose
            // Return does nothing teaches the user that Return does nothing.
            shortcut: .returnKey
        ) { [reveal] in reveal(url) }

        guard let manifest = record.manifest else {
            return SearchResult(
                id: record.id,
                kind: .plugin,
                title: url.lastPathComponent,
                subtitle: record.diagnostic?.message,
                iconSource: .systemSymbol("exclamationmark.triangle"),
                searchableTerms: [url.lastPathComponent],
                textScore: score,
                actions: [revealAction]
            )
        }

        return SearchResult(
            id: manifest.id,
            kind: .plugin,
            title: manifest.name,
            subtitle: manifest.description,
            iconSource: .systemSymbol(symbol(for: manifest)),
            searchableTerms: terms(of: record),
            textScore: score,
            actions: [revealAction],
            argument: manifest.input.mode.acceptsArgument
                ? ArgumentRequest(
                    placeholder: manifest.input.placeholder,
                    isRequired: manifest.input.mode == .required
                )
                : nil
        )
    }

    /// An unknown SF Symbol falls back rather than invalidating the plugin: the
    /// set of symbols depends on the macOS version, so a manifest valid today
    /// would otherwise break on an older Mac.
    private func symbol(for manifest: PluginManifest) -> String {
        guard
            let name = manifest.icon,
            NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        else {
            return Self.fallbackSymbol
        }
        return name
    }
}
