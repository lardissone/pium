import Foundation

/// Builds the Spotlight query and decides which of its results are worth
/// showing.
///
/// Everything here is pure so it can be tested without an index. Path
/// exclusions live in Swift rather than in the predicate deliberately: a
/// mistaken predicate fails silently by matching nothing, while a mistaken
/// function shows up in a test and in a stack trace.
enum SpotlightQuery {
    /// The PRD starts file search here. One character matches most of the disk.
    static let minimumQueryLength = 2

    /// Directory names that mean "this is machinery, not a document".
    private static let excludedComponents: Set<String> = [
        "Library",
        "node_modules",
        "Applications",
    ]

    static func predicate(for query: NormalizedQuery) -> NSPredicate {
        // `LIKE[cd]`, not `==[cd]`. `mdfind` documents `== "*term*"cd` as the
        // wildcard form, but that is a different parser: through `NSPredicate`
        // and `NSMetadataQuery`, `==` with wildcards matches nothing and `LIKE`
        // is the operator that works. Verified against a live index — do not
        // "fix" this to match the `mdfind` syntax.
        //
        // `%@` carries the text as an argument, so quotes, wildcards, and
        // apostrophes cannot change the shape of the query.
        //
        // One clause per word, rather than one clause for the whole query.
        // A single `*yo n*` asks the index for a name containing that exact
        // run of characters, space included — so `yo_nueva.jpg` was never
        // returned at all, and no amount of scoring downstream could rescue a
        // file the query never asked for (PIUM-111). Matching each word on its
        // own leaves the file free to separate them however it likes.
        //
        // Falls back to the folded string when the query has no words, which
        // is a query of pure punctuation.
        let words = query.tokens.isEmpty ? [query.folded] : query.tokens
        let clauses = words.map {
            NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\($0)*")
        }
        // One word gets its clause directly rather than an `AND` wrapped around
        // a single term. The wrapper is meaningless to read and not meaningless
        // to `NSMetadataQuery`: with it, a broad one-word search stopped
        // producing a first batch at all, and a stream nobody could get a value
        // out of is a hang rather than an error.
        let matchesName = clauses.count == 1
            ? clauses[0]
            : NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        // Applications have their own provider; showing them here would
        // duplicate every result.
        let isNotApplication = NSPredicate(
            format: "NOT (kMDItemContentTypeTree == %@)", "com.apple.application-bundle"
        )
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            matchesName, isNotApplication,
        ])
    }

    /// Whether a result is something a person was looking for.
    static func isPresentable(_ url: URL) -> Bool {
        if url.pathExtension == "app" { return false }

        for component in url.pathComponents {
            // Hidden directories and files: `.git`, `.config`, dotfiles.
            if component.hasPrefix("."), component != "." { return false }
            if excludedComponents.contains(component) { return false }
        }
        return true
    }

    /// Where the file lives, abbreviated with `~` the way the Finder writes it.
    static func subtitle(for url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}
