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
        // `%@` carries the text as an argument, so quotes, wildcards, and
        // apostrophes cannot change the shape of the query.
        let matchesName = NSPredicate(
            format: "kMDItemDisplayName LIKE[cd] %@", "*\(query.folded)*"
        )
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
