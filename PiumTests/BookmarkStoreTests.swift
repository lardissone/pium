import Testing
import Foundation
@testable import Pium

@Suite("Storing bookmarks")
@MainActor
struct BookmarkStoreTests {
    /// Each test gets an isolated defaults domain so runs cannot see each
    /// other's writes or the developer's real settings.
    private func makeStore() -> (BookmarkStore, Preferences, String) {
        let suiteName = "com.lardissone.pium.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = Preferences(defaults: defaults)
        return (BookmarkStore(preferences: preferences), preferences, suiteName)
    }

    private func bookmark(_ name: String) -> Bookmark {
        Bookmark(name: name, destination: .link("https://example.com/\(name)"))
    }

    @Test func afreshInstallHasNoBookmarks() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(store.bookmarks.isEmpty)
    }

    @Test func abookmarkSurvivesARelaunch() {
        let (store, preferences, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.add(bookmark("Notes"))

        // What a relaunch is, as far as this type is concerned: a second store
        // reading the same preferences.
        #expect(BookmarkStore(preferences: preferences).bookmarks.map(\.name) == ["Notes"])
    }

    @Test func editingABookmarkReplacesTheOneWithThatId() {
        let (store, preferences, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        var saved = bookmark("Notes")
        store.add(saved)
        saved.name = "Daily notes"
        store.update(saved)

        #expect(store.bookmarks.count == 1)
        #expect(BookmarkStore(preferences: preferences).bookmarks == [saved])
    }

    /// The id is what the frecency history is keyed by, so renaming has to keep
    /// it rather than replace the bookmark with a new one.
    @Test func renamingKeepsTheId() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        var saved = bookmark("Notes")
        let id = saved.id
        store.add(saved)
        saved.name = "Daily notes"
        store.update(saved)

        #expect(store.bookmarks.first?.id == id)
    }

    /// A bookmark the user deleted in another window is gone. Re-adding it as a
    /// side effect of saving a stale form would resurrect it.
    @Test func editingSomethingThatIsGoneAddsNothing() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.update(bookmark("Never added"))

        #expect(store.bookmarks.isEmpty)
    }

    @Test func removingABookmarkIsPermanent() {
        let (store, preferences, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let saved = bookmark("Notes")
        store.add(saved)
        store.add(bookmark("Other"))
        store.remove(saved.id)

        #expect(BookmarkStore(preferences: preferences).bookmarks.map(\.name) == ["Other"])
    }

    /// Sorted by the store rather than by whoever displays them, so two readers
    /// cannot disagree about the order. `localizedStandardCompare` is what the
    /// Finder sorts by: case-insensitive, and accented letters beside the
    /// letters they are.
    @Test func bookmarksAreKeptInTheOrderAPersonWouldExpect() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.add(bookmark("banana"))
        store.add(bookmark("Apple"))
        store.add(bookmark("ábaco"))

        #expect(store.bookmarks.map(\.name) == ["ábaco", "Apple", "banana"])
    }
}

@Suite("Bookmarks in preferences")
@MainActor
struct BookmarkPreferencesTests {
    private func makePreferences() -> (Preferences, UserDefaults, String) {
        let suiteName = "com.lardissone.pium.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (Preferences(defaults: defaults), defaults, suiteName)
    }

    @Test func bookmarksSurviveAWriteAndReload() {
        let (preferences, defaults, suite) = makePreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let bookmarks = [
            Bookmark(name: "Notes", destination: .path("~/notes.md")),
            Bookmark(
                name: "Search",
                destination: .link("https://x.com/?q={{input}}"),
                keywords: ["find"],
                openWith: "com.apple.Safari"
            ),
        ]
        preferences.bookmarks = bookmarks

        #expect(Preferences(defaults: defaults).bookmarks == bookmarks)
    }

    /// Stored data that cannot be read is somebody's hand edit or a format from
    /// a version that no longer exists. An empty list loses their bookmarks;
    /// a crash loses the launcher, which is worse.
    @Test func unreadableStoredDataReadsAsNoBookmarks() {
        let (preferences, defaults, suite) = makePreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: "pium.bookmarks")

        #expect(preferences.bookmarks.isEmpty)
    }
}
