import Foundation

/// The bookmarks the user made, in memory and on their way to preferences.
///
/// Observable because the Bookmarks section of Settings is a list of exactly
/// this, and adding one there has to show up in it without anybody asking.
@MainActor
@Observable
final class BookmarkStore {
    private let preferences: Preferences

    /// Kept in the order a person reads, so that no two readers can disagree
    /// about it. `localizedStandardCompare` is what the Finder sorts by:
    /// case-insensitive, and accented letters beside the letters they are.
    private(set) var bookmarks: [Bookmark]

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        self.bookmarks = Self.sorted(preferences.bookmarks)
    }

    func add(_ bookmark: Bookmark) {
        save(bookmarks + [bookmark])
    }

    /// Replaces the bookmark carrying this one's id.
    ///
    /// A bookmark that is no longer there is not added back: it was deleted
    /// while a form still had it open, and saving that form should not
    /// resurrect it.
    func update(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        var updated = bookmarks
        updated[index] = bookmark
        save(updated)
    }

    func remove(_ id: UUID) {
        save(bookmarks.filter { $0.id != id })
    }

    private func save(_ updated: [Bookmark]) {
        bookmarks = Self.sorted(updated)
        preferences.bookmarks = bookmarks
    }

    private static func sorted(_ bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
