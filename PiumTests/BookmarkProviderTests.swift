import Testing
import Foundation
import AppKit
@testable import Pium

@Suite("Searching bookmarks")
@MainActor
struct BookmarkProviderTests {
    private func makeStore(_ bookmarks: [Bookmark]) -> (BookmarkStore, String) {
        let suiteName = "com.lardissone.pium.tests.\(UUID().uuidString)"
        let store = BookmarkStore(preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!))
        for bookmark in bookmarks { store.add(bookmark) }
        return (store, suiteName)
    }

    private func results(
        _ store: BookmarkStore,
        _ text: String,
        open: @escaping @Sendable @MainActor (Bookmark, String) -> Void = { _, _ in },
        copy: @escaping @Sendable @MainActor (String) -> Void = { _ in }
    ) async -> [SearchResult] {
        let provider = BookmarkProvider(store: store, open: open, copy: copy)
        var last: [SearchResult] = []
        for await batch in provider.results(for: TextNormalizer.query(text)) { last = batch }
        return last
    }

    private func bookmark(
        _ name: String,
        _ destination: BookmarkDestination = .link("https://example.com"),
        keywords: [String] = []
    ) -> Bookmark {
        Bookmark(name: name, destination: destination, keywords: keywords)
    }

    @Test func abookmarkIsFoundByItsName() async {
        let (store, suite) = makeStore([bookmark("Home Assistant")])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(await results(store, "home").map(\.title) == ["Home Assistant"])
    }

    @Test func abookmarkIsFoundByAKeyword() async {
        let (store, suite) = makeStore([bookmark("Home Assistant", keywords: ["hass", "casa"])])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(await results(store, "casa").map(\.title) == ["Home Assistant"])
    }

    /// The same hard text gate every other provider applies. Without it a
    /// bookmark would sit in the list for a query that has nothing to do with
    /// it, and rank first while it was there.
    @Test func textThatMatchesNothingReturnsNothing() async {
        let (store, suite) = makeStore([bookmark("Home Assistant")])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(await results(store, "zzzzz").isEmpty)
    }

    @Test func anEmptyQueryReturnsNothing() async {
        let (store, suite) = makeStore([bookmark("Home Assistant")])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(await results(store, "").isEmpty)
    }

    @Test func abookmarkIsARowOfItsOwnKind() async {
        let (store, suite) = makeStore([bookmark("Home Assistant")])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(await results(store, "home").first?.kind == .bookmark)
    }

    /// Return opens it, and what was typed in argument mode goes with it.
    @Test func returnOpensTheBookmarkWithWhatWasTyped() async {
        let (store, suite) = makeStore([
            bookmark("Search", .link("https://x.com/?q={{input}}"))
        ])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let opened = Recorder()
        let found = await results(store, "search", open: { bookmark, input in
            opened.record("\(bookmark.name)|\(input)")
        })
        let action = try? #require(found.first?.primaryAction)
        action?.perform("hola")

        #expect(opened.recorded == ["Search|hola"])
    }

    @Test func commandReturnCopiesTheResolvedDestination() async {
        let (store, suite) = makeStore([
            bookmark("Search", .link("https://x.com/?q={{input}}"))
        ])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let copied = Recorder()
        let found = await results(store, "search", copy: { copied.record($0) })
        let action = found.first?.actions.first { $0.shortcut == .commandReturn }
        action?.perform("a b")

        #expect(copied.recorded == ["https://x.com/?q=a%20b"])
    }

    /// Derived from the destination, and required: opening half a URL is worse
    /// than not opening.
    @Test func abookmarkThatInterpolatesTheInputAsksForOne() async {
        let (store, suite) = makeStore([
            bookmark("Search", .link("https://x.com/?q={{input}}")),
            bookmark("Plain", .link("https://example.com")),
        ])
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let asking = await results(store, "search").first
        #expect(asking?.argument?.isRequired == true)
        #expect(await results(store, "plain").first?.argument == nil)
    }
}

/// Collects what a closure was called with, so an action can be tested by what
/// it did rather than by what it is.
@MainActor
final class Recorder {
    private(set) var recorded: [String] = []
    func record(_ value: String) { recorded.append(value) }
}

@Suite("A bookmark's icon")
@MainActor
struct BookmarkIconTests {
    private let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    private let safari = URL(fileURLWithPath: "/Applications/Safari.app")

    /// The file an icon points at, by path rather than by URL: a directory URL
    /// carries a trailing slash and one built from a bare path does not, and
    /// the difference means nothing to `NSWorkspace.icon(forFile:)`.
    private func iconPath(_ source: IconSource) -> String? {
        guard case .fileIcon(let url) = source else { return nil }
        return url.path
    }

    /// The cascade, with any favicon in front of it set aside.
    ///
    /// These tests are about which application wins, and a web link now wears
    /// a favicon over that answer — so the answer they are asking about is the
    /// fallback.
    private func cascade(
        for bookmark: Bookmark,
        installed: [String: URL] = [:],
        opener: URL? = nil
    ) -> IconSource {
        let source = source(for: bookmark, installed: installed, opener: opener)
        guard case .favicon(_, let fallback) = source else { return source }
        return fallback
    }

    private func source(
        for bookmark: Bookmark,
        installed: [String: URL] = [:],
        opener: URL? = nil
    ) -> IconSource {
        BookmarkIcon.source(
            for: bookmark,
            applicationForBundleIdentifier: { installed[$0] },
            applicationToOpen: { _ in opener }
        )
    }

    /// The application the user named wins outright. They chose it for this
    /// bookmark, and that choice is the most specific thing there is to show.
    @Test func theApplicationTheUserChoseComesFirst() {
        let bookmark = Bookmark(
            name: "Docs",
            destination: .link("https://example.com"),
            openWith: "com.google.Chrome"
        )

        #expect(
            cascade(for: bookmark, installed: ["com.google.Chrome": chrome], opener: safari)
                == .fileIcon(chrome)
        )
    }

    /// Named an application that is no longer installed: fall through rather
    /// than show nothing.
    @Test func anApplicationThatIsGoneFallsThrough() {
        let bookmark = Bookmark(
            name: "Docs",
            destination: .link("https://example.com"),
            openWith: "com.google.Chrome"
        )

        #expect(cascade(for: bookmark, installed: [:], opener: safari) == .fileIcon(safari))
    }

    @Test func alinkOtherwiseShowsWhateverWouldOpenIt() {
        let bookmark = Bookmark(name: "Docs", destination: .link("https://example.com"))

        #expect(cascade(for: bookmark, opener: safari) == .fileIcon(safari))
    }

    /// A path shows the thing itself rather than the application that would
    /// open it: a folder should look like a folder.
    @Test func apathThatExistsShowsItsOwnIcon() throws {
        let directory = URL.temporaryDirectory.appending(path: "pium-icon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = Bookmark(name: "Scratch", destination: .path(directory.path))

        #expect(iconPath(source(for: bookmark, opener: safari)) == directory.path)
    }

    /// A site's own icon says more than the browser that would open it, so it
    /// goes in front of everything — including an application the user chose,
    /// which is about where it opens rather than about what it is.
    @Test func anHttpLinkAsksTheSiteForItsIcon() {
        let bookmark = Bookmark(
            name: "Docs",
            destination: .link("https://example.com/a"),
            openWith: "com.google.Chrome"
        )

        #expect(
            source(for: bookmark, installed: ["com.google.Chrome": chrome], opener: safari)
                == .favicon(host: "example.com", fallback: .fileIcon(chrome))
        )
    }

    /// Only the web has favicons. Everything else goes straight to the cascade
    /// rather than asking a host that will not answer.
    @Test func nothingButTheWebIsAskedForAnIcon() throws {
        let scheme = Bookmark(name: "Vault", destination: .link("obsidian://open?vault=x"))
        #expect(source(for: scheme, opener: safari) == .fileIcon(safari))

        let directory = URL.temporaryDirectory.appending(path: "pium-icon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = Bookmark(name: "Scratch", destination: .path(directory.path))
        #expect(iconPath(source(for: path, opener: safari)) == directory.path)
    }

    /// Nothing resolvable — a path that is not there, or a link nothing
    /// handles. A symbol says "bookmark" rather than leaving the row blank.
    @Test func nothingResolvableFallsBackToASymbol() {
        let missing = Bookmark(name: "Gone", destination: .path("/nowhere/at/all"))
        let unhandled = Bookmark(name: "Odd", destination: .link("zzz://whatever"))

        #expect(source(for: missing) == .systemSymbol("folder"))
        #expect(source(for: unhandled) == .systemSymbol("link"))
    }
}
