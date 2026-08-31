import Foundation

/// What a refused form says, in the words of somebody filling in fields.
///
/// Here rather than on the error types themselves: `ArgumentTemplateError`
/// carries what was wrong and leaves the wording to whoever shows it, and a
/// plugin's author reading a diagnostic in the result list needs different
/// words from a person looking at the field they just typed into.
extension BookmarkDraftProblem {
    var message: String {
        switch self {
        case .nameIsEmpty:
            String(localized: "bookmarks.problem.nameIsEmpty")
        case .destination(let error):
            error.message
        }
    }
}

extension BookmarkDestinationError {
    var message: String {
        switch self {
        case .empty:
            String(localized: "bookmark.destination.empty")
        case .unrecognized(let text):
            String(localized: "bookmark.destination.unrecognized \(text)")
        case .invalidTemplate(.unclosedPlaceholder(let template)):
            String(localized: "bookmark.template.unclosed \(template)")
        case .invalidTemplate(.unknownVariable(let name)):
            String(localized: "bookmark.template.unknownVariable \(name)")
        case .invalidTemplate(.unknownFilter(let name)):
            String(localized: "bookmark.template.unknownFilter \(name)")
        }
    }
}
