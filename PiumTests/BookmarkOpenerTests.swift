import Testing
import Foundation
@testable import Pium

@Suite("Opening a bookmark")
@MainActor
struct BookmarkOpenerTests {
    private let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")

    /// What the opener asked the system to do, so the tests watch behaviour
    /// rather than reaching for a real `NSWorkspace`.
    @MainActor
    final class SystemSpy {
        var openedPlainly: [URL] = []
        var openedWith: [(url: URL, application: URL)] = []
        var reported: [HUDPresentation] = []
    }

    private func makeOpener(
        _ spy: SystemSpy,
        installed: [String: URL] = [:]
    ) -> BookmarkOpener {
        BookmarkOpener(
            applicationForBundleIdentifier: { installed[$0] },
            open: { spy.openedPlainly.append($0) },
            openWith: { spy.openedWith.append((url: $0, application: $1)) },
            report: { spy.reported.append($0) }
        )
    }

    @Test func alinkIsOpenedAsWritten() {
        let spy = SystemSpy()
        makeOpener(spy).open(
            Bookmark(name: "Docs", destination: .link("https://example.com/a")),
            input: ""
        )

        #expect(spy.openedPlainly.map(\.absoluteString) == ["https://example.com/a"])
        #expect(spy.reported.isEmpty)
    }

    @Test func theArgumentReachesTheLinkEncoded() {
        let spy = SystemSpy()
        makeOpener(spy).open(
            Bookmark(name: "Search", destination: .link("https://x.com/?q={{input}}")),
            input: "a b&c"
        )

        #expect(spy.openedPlainly.map(\.absoluteString) == ["https://x.com/?q=a%20b%26c"])
    }

    /// A path is expanded and opened as a file, not handed over as text.
    @Test func apathIsOpenedAsAFile() {
        let spy = SystemSpy()
        makeOpener(spy).open(
            Bookmark(name: "Notes", destination: .path("~/notes.md")),
            input: ""
        )

        let opened = spy.openedPlainly.first
        #expect(opened?.isFileURL == true)
        #expect(opened?.path == (NSString(string: "~/notes.md").expandingTildeInPath))
    }

    @Test func theChosenApplicationIsUsedWhenItIsInstalled() {
        let spy = SystemSpy()
        let bookmark = Bookmark(
            name: "Docs",
            destination: .link("https://example.com"),
            openWith: "com.google.Chrome"
        )
        makeOpener(spy, installed: ["com.google.Chrome": chrome]).open(bookmark, input: "")

        #expect(spy.openedWith.map(\.application) == [chrome])
        #expect(spy.openedPlainly.isEmpty)
        #expect(spy.reported.isEmpty)
    }

    /// Doing nothing would be worse: the user asked for this to open. It opens,
    /// and is told which application was missing rather than left wondering why
    /// it came up somewhere else.
    @Test func anApplicationThatIsGoneStillOpensAndSaysSo() {
        let spy = SystemSpy()
        let bookmark = Bookmark(
            name: "Docs",
            destination: .link("https://example.com"),
            openWith: "com.google.Chrome"
        )
        makeOpener(spy, installed: [:]).open(bookmark, input: "")

        #expect(spy.openedPlainly.map(\.absoluteString) == ["https://example.com"])
        #expect(spy.openedWith.isEmpty)
        #expect(spy.reported.count == 1)
        #expect(spy.reported.first?.kind == .failure)
        #expect(spy.reported.first?.body.contains("com.google.Chrome") == true)
    }

    /// Percent-encoding saves most of what a person can type, and not all of
    /// it. Opening nothing while saying nothing is the one outcome to avoid.
    @Test func adestinationThatDoesNotParseOpensNothingAndSaysWhy() {
        let spy = SystemSpy()
        makeOpener(spy).open(
            Bookmark(name: "Broken", destination: .link("https://exa mple.com/{{input}}")),
            input: ""
        )

        #expect(spy.openedPlainly.isEmpty)
        #expect(spy.openedWith.isEmpty)
        #expect(spy.reported.first?.kind == .failure)
        #expect(spy.reported.first?.title.contains("Broken") == true)
    }
}
