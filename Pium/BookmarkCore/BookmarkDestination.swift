import Foundation

/// Where a bookmark points: something with a scheme, or somewhere on this Mac.
///
/// Two cases rather than one string, because the difference is real at both
/// ends — what text has to look like to be one of them, and what happens to
/// the user's argument when it lands inside.
enum BookmarkDestination: Sendable, Equatable, Codable {
    case link(String)
    case path(String)
}

/// Why a destination could not be read.
///
/// Data rather than a sentence, the same way `ArgumentTemplateError` is: the
/// form wording it sits beside the field it is about, and that wording is not
/// this type's business.
enum BookmarkDestinationError: Error, Sendable, Equatable {
    case empty
    case unrecognized(String)
    case invalidTemplate(ArgumentTemplateError)
}

extension BookmarkDestination {
    /// The text as the user wrote it, placeholders and all.
    var template: String {
        switch self {
        case .link(let text), .path(let text): text
        }
    }

    /// Reads text into a destination, and proves its template will resolve.
    ///
    /// Classifying happens here, once, when a bookmark is saved — rather than
    /// when it is opened. That is what lets the form tell somebody that what
    /// they typed is neither a link nor a path, at the moment they can still
    /// see the field they typed it into.
    static func parse(_ text: String) -> Result<BookmarkDestination, BookmarkDestinationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let destination: BookmarkDestination
        // A path is recognised first. A colon is legal in a file name, so
        // `/Users/someone/a:b` would otherwise read as a scheme.
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            destination = .path(trimmed)
        } else if hasScheme(trimmed) {
            destination = .link(trimmed)
        } else {
            // Pium does not guess that a bare host meant `https://`. Guessing
            // right most of the time means opening the wrong thing the rest of
            // it, and the two characters that settle it are the author's to
            // type.
            return .failure(.unrecognized(trimmed))
        }

        if case .failure(let error) = destination.tokens() {
            return .failure(.invalidTemplate(error))
        }
        return .success(destination)
    }

    /// A scheme as RFC 3986 defines one: a letter, then letters, digits, `+`,
    /// `-` or `.`, up to the first colon. Deliberately not a list of known
    /// schemes — `obsidian://` and `raycast://` are exactly the point.
    private static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[text.startIndex..<colon]
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.dropFirst().allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "."
        }
    }

    /// What a placeholder written without a filter means here.
    ///
    /// A link percent-encodes, so nothing a person types can change the shape
    /// of the URL it lands in. A path does not: a file name is not a URL, and
    /// encoding one would look for a file whose name contains the escapes.
    private var defaultFilter: ArgumentTemplateFilter {
        switch self {
        case .link: .urlEncode
        case .path: .raw
        }
    }

    private func tokens() -> Result<[ArgumentTemplateToken], ArgumentTemplateError> {
        ArgumentTemplate.parse(template, defaultFilter: defaultFilter)
    }

    /// Whether this destination interpolates what the user types.
    ///
    /// Derived rather than declared: a bookmark that takes an argument is
    /// exactly one whose destination has a place to put it, and a second
    /// stored flag could only ever disagree with the text.
    var takesArgument: Bool {
        guard case .success(let tokens) = tokens() else { return false }
        return tokens.contains { token in
            if case .input = token { return true }
            return false
        }
    }

    /// The destination with the argument in it, ready to be opened.
    ///
    /// `nil` when the template does not parse, which `parse` above rules out
    /// for anything Pium saved — it remains reachable for a stored value
    /// somebody edited by hand, and opening nothing beats opening a URL with
    /// `{{input}}` still in it.
    func resolved(input: String) -> String? {
        guard case .success(let tokens) = tokens() else { return nil }
        return ArgumentTemplate.resolve(tokens, input: input)
    }
}
