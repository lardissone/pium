import Foundation

/// A file or folder the user does not want to see among file results.
///
/// An entry says what it is by the way it is written, so the everyday cases
/// need no pattern syntax: `node_modules` is a folder name and matches at any
/// depth, `~/Developer/archive` is one place and takes its contents with it,
/// and anything holding `*`, `?`, or `[` is a pattern for the rest.
///
/// Matching is pure and lives here rather than in the Spotlight predicate, for
/// the reason `SpotlightQuery` documents: a mistaken predicate fails silently
/// by matching nothing, while a mistaken function shows up in a test.
enum FolderExclusion {
    /// What makes an entry a pattern rather than a literal.
    private static let patternCharacters: Set<Character> = ["*", "?", "["]

    /// An entry as it should be stored, or `nil` when there is nothing to
    /// store.
    ///
    /// A path pasted from a terminal or dragged onto the field arrives with a
    /// trailing slash or a stray space as often as not, and the same folder
    /// stored twice reads as two entries that exclude exactly the same files.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A pattern is kept exactly as written. Expanding or tidying it would
        // change what it matches.
        guard !isPattern(trimmed) else { return trimmed }
        guard trimmed.contains("/") else { return trimmed }

        let expanded = (trimmed as NSString).expandingTildeInPath
        // With a slash in it the entry is a path, and a relative path has
        // nothing here to be relative to.
        guard expanded.hasPrefix("/") else { return nil }
        return expanded.count > 1 && expanded.hasSuffix("/")
            ? String(expanded.dropLast())
            : expanded
    }

    /// Whether a result falls under any of the entries.
    static func excludes(_ url: URL, matching entries: [String]) -> Bool {
        entries.contains { matches(url.path, entry: $0) }
    }

    /// Every comparison here ignores case, because the volume Pium searches
    /// does: an exclusion that told `Build` from `build` would look like it
    /// was being ignored at random.
    private static func matches(_ path: String, entry: String) -> Bool {
        if isPattern(entry) {
            return fnmatch(entry, path, FNM_CASEFOLD) == 0
        }
        if entry.contains("/") {
            // The separator is part of the comparison, which is what keeps
            // `~/Dev` from taking `~/Development` with it.
            return path.compare(entry, options: .caseInsensitive) == .orderedSame
                || path.lowercased().hasPrefix(entry.lowercased() + "/")
        }
        // A name matches a whole component or nothing, so excluding `build`
        // leaves `build-notes.md` alone.
        return path.split(separator: "/").contains {
            $0.compare(entry, options: .caseInsensitive) == .orderedSame
        }
    }

    private static func isPattern(_ entry: String) -> Bool {
        entry.contains(where: patternCharacters.contains)
    }
}
