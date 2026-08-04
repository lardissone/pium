import Foundation

/// A query after normalization. The raw form is kept because plugins in
/// Phase 4 receive exactly what the user typed.
struct NormalizedQuery: Sendable, Equatable {
    let raw: String
    let folded: String

    var isEmpty: Bool { folded.isEmpty }
}

/// A candidate string prepared once, so scoring never re-derives it.
struct NormalizedCandidate: Sendable, Equatable {
    let folded: String
    let tokens: [String]
    /// First letter of each token, e.g. "vsc" for "Visual Studio Code".
    let acronym: String
}

/// The single normalization pipeline for queries and candidates.
///
/// Splitting this from `FuzzyMatcher` keeps the matcher's tests pure data and
/// lets Phase 4 reuse both for plugin names and aliases.
enum TextNormalizer {
    static func query(_ string: String) -> NormalizedQuery {
        NormalizedQuery(raw: string, folded: fold(string))
    }

    static func candidate(_ string: String) -> NormalizedCandidate {
        let tokens = tokenize(string)
        return NormalizedCandidate(
            folded: fold(string),
            tokens: tokens,
            acronym: String(tokens.compactMap(\.first))
        )
    }

    /// Lowercases, strips diacritics, and collapses whitespace.
    ///
    /// Folding is locale-insensitive on purpose: a Spanish user searching an
    /// English application name, and the reverse, must both work.
    static func fold(_ string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Splits on whitespace, punctuation, and camel-case boundaries.
    static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for character in string {
            if character.isWhitespace || (character.isPunctuation || character.isSymbol) {
                if !current.isEmpty { tokens.append(current) }
                current = ""
                continue
            }

            // A capital after a lowercase starts a new word: "QuickTime".
            // A run of capitals stays together: "IINA".
            if let previous = current.last,
               character.isUppercase,
               previous.isLowercase || previous.isNumber {
                tokens.append(current)
                current = ""
            }

            current.append(character)
        }

        if !current.isEmpty { tokens.append(current) }
        return tokens.map { fold($0) }.filter { !$0.isEmpty }
    }
}
