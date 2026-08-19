import Foundation

/// Which provider produced a result. The order of the cases is also the
/// tie-break order the PRD fixes for equal scores.
enum ResultKind: String, Sendable, CaseIterable {
    case bookmark
    case plugin
    case application
    case file

    /// Lower sorts first when text scores tie.
    var tieBreakRank: Int {
        switch self {
        // A bookmark is the only result the user made by hand, and named
        // themselves. An equal text score means it is what they meant.
        case .bookmark: 0
        case .plugin: 1
        case .application: 2
        case .file: 3
        }
    }

    /// What this kind is called out loud. The row's icon carries it visually
    /// and is hidden from VoiceOver as decoration, so without words the
    /// difference between an app called Notes and a file called Notes is
    /// simply lost.
    var spokenName: String {
        switch self {
        case .bookmark: String(localized: "result.kind.bookmark")
        case .plugin: String(localized: "result.kind.plugin")
        case .application: String(localized: "result.kind.application")
        case .file: String(localized: "result.kind.file")
        }
    }
}

/// Where a row's icon comes from. Resolving it is the view's job, so the model
/// stays free of AppKit and remains `Sendable`.
enum IconSource: Sendable, Equatable {
    /// Anything with a file icon: an application bundle, a document, a folder.
    /// Resolved with `NSWorkspace.icon(forFile:)`, which has an answer for all
    /// of them.
    case fileIcon(URL)
    case systemSymbol(String)
    /// A symbol for a row that reports a problem. Separate from `systemSymbol`
    /// so the row can colour it without inferring intent from a symbol name.
    case warningSymbol(String)
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

    /// The message to show before this result's primary action runs, from a
    /// plugin's `confirmBeforeRun` (PRD §10.4). `nil` for everything that
    /// simply runs. Asked every time — nothing about a past confirmation is
    /// carried on this value or anywhere else.
    let confirmation: String?

    init(
        id: String,
        kind: ResultKind,
        title: String,
        subtitle: String?,
        iconSource: IconSource,
        searchableTerms: [String],
        textScore: Double,
        actions: [ResultAction],
        argument: ArgumentRequest? = nil,
        confirmation: String? = nil
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
        self.confirmation = confirmation
    }

    /// What `Return` runs. By convention the first action.
    var primaryAction: ResultAction? { actions.first }

    /// How this row reads to a screen reader: the title, what kind of thing it
    /// is, and whatever the subtitle was distinguishing it from.
    ///
    /// Assembled here rather than in the view so it can be read in a test. The
    /// view combines its own children by default, which produces the title and
    /// subtitle and silently drops the kind with the icon.
    var accessibilityDescription: String {
        [title, kind.spokenName, subtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
