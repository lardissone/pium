import Foundation

/// One thing the user picked, for one thing they typed.
///
/// This is the entire privacy surface of Pium's learning: a result ID, the
/// normalized query that led to it, how often, and when last. Abandoned
/// queries and plugin arguments are never recorded — PRD §7.3.
struct FrecencyEntry: Codable, Sendable, Equatable {
    let resultID: String
    /// The folded query, not what was typed. Storing the raw text would keep
    /// case and accents that add nothing and reveal more.
    let query: String
    var selectionCount: Int
    var lastSelected: Date
}

/// An immutable view of usage, handed to the ranker.
///
/// The ranker never sees the store, so ranking cannot touch the disk or mutate
/// anything, which is what keeps it a pure function.
struct UsageSnapshot: Sendable {
    private let byResultID: [String: [FrecencyEntry]]

    init(entries: [FrecencyEntry]) {
        byResultID = Dictionary(grouping: entries, by: \.resultID)
    }

    func entries(forResultID resultID: String) -> [FrecencyEntry] {
        byResultID[resultID] ?? []
    }

    var isEmpty: Bool { byResultID.isEmpty }
}
