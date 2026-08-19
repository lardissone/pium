import Foundation

/// A bookmark while it is being typed.
///
/// Every field is text, because that is what a form holds — including the ones
/// that become something else. Turning it into a `Bookmark` is where the text
/// is judged, so the form can be half-finished without anything downstream
/// having to cope with half a bookmark.
struct BookmarkDraft: Equatable {
    var name: String = ""
    var destination: String = ""
    /// Comma separated, because somebody adding two aliases should not have to
    /// meet a list editor to do it.
    var keywords: String = ""
    /// The bundle identifier of the chosen application; `nil` is "whatever
    /// macOS would use".
    var openWith: String?

    init(name: String = "", destination: String = "", keywords: String = "", openWith: String? = nil) {
        self.name = name
        self.destination = destination
        self.keywords = keywords
        self.openWith = openWith
    }

    /// Opens an existing bookmark into the form it was made in.
    init(_ bookmark: Bookmark) {
        self.name = bookmark.name
        self.destination = bookmark.destination.template
        self.keywords = bookmark.keywords.joined(separator: ", ")
        self.openWith = bookmark.openWith
    }

    func bookmark(id: UUID) -> Result<Bookmark, BookmarkDraftProblem> {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.nameIsEmpty) }

        switch BookmarkDestination.parse(destination) {
        case .failure(let error):
            return .failure(.destination(error))
        case .success(let destination):
            return .success(
                Bookmark(
                    id: id,
                    name: name,
                    destination: destination,
                    keywords: Self.keywords(from: keywords),
                    openWith: openWith
                )
            )
        }
    }

    /// How Pium read the destination, for the line under the field.
    ///
    /// Structured rather than a sentence: the wording belongs to the view, and
    /// the decision belongs in a test.
    var reading: DestinationReading {
        guard !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard case .success(let parsed) = BookmarkDestination.parse(destination) else {
            return .unreadable
        }
        switch parsed {
        case .link: return .link(takesArgument: parsed.takesArgument)
        case .path: return .path(takesArgument: parsed.takesArgument)
        }
    }

    private static func keywords(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Why a form cannot be saved yet.
enum BookmarkDraftProblem: Error, Equatable {
    case nameIsEmpty
    case destination(BookmarkDestinationError)
}

/// What the form makes of the destination as it is typed.
enum DestinationReading: Equatable {
    case empty
    case link(takesArgument: Bool)
    case path(takesArgument: Bool)
    case unreadable
}
