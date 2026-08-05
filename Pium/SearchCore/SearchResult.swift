import Foundation

/// Which provider produced a result. The order of the cases is also the
/// tie-break order the PRD fixes for equal scores.
enum ResultKind: String, Sendable, CaseIterable {
    case plugin
    case application
    case file

    /// Lower sorts first when text scores tie.
    var tieBreakRank: Int {
        switch self {
        case .plugin: 0
        case .application: 1
        case .file: 2
        }
    }
}

/// Where a row's icon comes from. Resolving it is the view's job, so the model
/// stays free of AppKit and remains `Sendable`.
enum IconSource: Sendable, Equatable {
    case applicationBundle(URL)
    case systemSymbol(String)
}

/// A result that takes a free-form argument before it can run.
///
/// On `SearchResult` rather than on a plugin type so the launcher's argument
/// mode does not have to know what a plugin is — the same way actions are
/// values the menu renders without knowing what they do.
struct ArgumentRequest: Sendable, Equatable {
    let placeholder: String?
    /// When true, the result cannot run without one.
    let isRequired: Bool
}

/// One row in the unified result list.
///
/// `id` must be stable across queries: selection is tracked by ID so the user's
/// choice survives the list reordering as new results arrive.
struct SearchResult: Identifiable, Sendable {
    let id: String
    let kind: ResultKind
    let title: String
    let subtitle: String?
    let iconSource: IconSource
    /// Everything the matcher may score against: title, aliases, keywords.
    let searchableTerms: [String]
    let textScore: Double
    let actions: [ResultAction]

    /// Present when this result takes an argument. `nil` for everything that
    /// simply runs.
    let argument: ArgumentRequest?

    init(
        id: String,
        kind: ResultKind,
        title: String,
        subtitle: String?,
        iconSource: IconSource,
        searchableTerms: [String],
        textScore: Double,
        actions: [ResultAction],
        argument: ArgumentRequest? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.iconSource = iconSource
        self.searchableTerms = searchableTerms
        self.textScore = textScore
        self.actions = actions
        self.argument = argument
    }

    /// What `Return` runs. By convention the first action.
    var primaryAction: ResultAction? { actions.first }
}
