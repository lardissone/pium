import Testing
import Foundation
@testable import Pium

@Suite("Bookmark destinations")
struct BookmarkDestinationTests {
    private func parsed(_ text: String) throws -> BookmarkDestination {
        try BookmarkDestination.parse(text).get()
    }

    @Test func textCarryingASchemeIsALink() throws {
        #expect(try parsed("https://example.com") == .link("https://example.com"))
        #expect(try parsed("mailto:someone@example.com") == .link("mailto:someone@example.com"))
        #expect(try parsed("obsidian://open?vault=notes") == .link("obsidian://open?vault=notes"))
    }

    @Test func textStartingAtTheRootOrTheHomeFolderIsAPath() throws {
        #expect(try parsed("/Users/someone/notes.md") == .path("/Users/someone/notes.md"))
        #expect(try parsed("~/Documents") == .path("~/Documents"))
    }

    /// A path is recognised before a scheme is looked for. A colon is legal in
    /// a file name, and `/Users/someone/a:b` is a file rather than something
    /// with a scheme called `/Users/someone/a`.
    @Test func aPathWithAColonInItIsStillAPath() throws {
        #expect(try parsed("/Users/someone/a:b") == .path("/Users/someone/a:b"))
    }

    /// What a person pastes carries the spaces around it.
    @Test func surroundingWhitespaceIsTrimmed() throws {
        #expect(try parsed("  https://example.com \n") == .link("https://example.com"))
    }

    /// Neither a link nor a path. Pium does not guess that a bare host was
    /// meant to be `https://` — the form says it cannot read this, and the
    /// person adds the two characters that make it unambiguous.
    @Test func textThatIsNeitherIsRejected() {
        #expect(BookmarkDestination.parse("example.com").failure == .unrecognized("example.com"))
        #expect(BookmarkDestination.parse("notes.md").failure == .unrecognized("notes.md"))
    }

    @Test func nothingIsRejectedAsEmpty() {
        #expect(BookmarkDestination.parse("").failure == .empty)
        #expect(BookmarkDestination.parse("   \n ").failure == .empty)
    }

    /// A destination is parsed once, when it is saved, so nothing downstream
    /// has to carry a template that was never going to resolve.
    @Test func aBrokenTemplateIsRejected() {
        #expect(
            BookmarkDestination.parse("https://x.com/?q={{input").failure
                == .invalidTemplate(.unclosedPlaceholder("https://x.com/?q={{input"))
        )
        #expect(
            BookmarkDestination.parse("https://x.com/?q={{clipboard}}").failure
                == .invalidTemplate(.unknownVariable("clipboard"))
        )
    }
}

@Suite("What a bookmark asks for")
struct BookmarkArgumentTests {
    private func parsed(_ text: String) throws -> BookmarkDestination {
        try BookmarkDestination.parse(text).get()
    }

    @Test func adestinationInterpolatingTheInputTakesAnArgument() throws {
        #expect(try parsed("https://x.com/?q={{input}}").takesArgument)
        #expect(try parsed("~/Documents/{{input}}.pdf").takesArgument)
    }

    @Test func adestinationWithoutItTakesNone() throws {
        #expect(try parsed("https://x.com/").takesArgument == false)
        #expect(try parsed("/Users/someone/notes.md").takesArgument == false)
    }
}

@Suite("Resolving a destination")
struct BookmarkResolutionTests {
    private func parsed(_ text: String) throws -> BookmarkDestination {
        try BookmarkDestination.parse(text).get()
    }

    /// In a link the argument is percent-encoded without being asked for, so
    /// that what a person types cannot change the shape of the URL it lands in.
    @Test func aLinkPercentEncodesTheArgument() throws {
        #expect(
            try parsed("https://x.com/?q={{input}}").resolved(input: "a b&c")
                == "https://x.com/?q=a%20b%26c"
        )
    }

    /// A path is not a URL. Encoding a file name would look for a file whose
    /// name contains the escapes.
    @Test func apathTakesTheArgumentAsItWasTyped() throws {
        #expect(
            try parsed("~/Documents/{{input}}.pdf").resolved(input: "my notes")
                == "~/Documents/my notes.pdf"
        )
    }

    /// The way out for a link whose argument is meant to be part of the path
    /// rather than a value inside it: `owner/repo` has to keep its slash.
    @Test func alinkCanAskForTheArgumentUnencoded() throws {
        #expect(
            try parsed("https://github.com/{{input|raw}}").resolved(input: "lardissone/pium")
                == "https://github.com/lardissone/pium"
        )
    }

    @Test func adestinationWithNoArgumentResolvesToItself() throws {
        #expect(try parsed("https://x.com/").resolved(input: "") == "https://x.com/")
    }
}

@Suite("A bookmark")
struct BookmarkTests {
    /// Bookmarks are stored as JSON, so the destination's two cases have to
    /// survive the round trip that storage is.
    @Test func abookmarkSurvivesBeingWrittenAndReadBack() throws {
        let bookmark = Bookmark(
            name: "Search YouTube",
            destination: .link("https://www.youtube.com/results?search_query={{input}}"),
            keywords: ["yt", "video"],
            openWith: "com.google.Chrome"
        )

        let restored = try JSONDecoder().decode(
            Bookmark.self, from: try JSONEncoder().encode(bookmark)
        )

        #expect(restored == bookmark)
    }

    @Test func apathBookmarkSurvivesTheSameRoundTrip() throws {
        let bookmark = Bookmark(name: "Notes", destination: .path("~/Documents/notes.md"))
        let restored = try JSONDecoder().decode(
            Bookmark.self, from: try JSONEncoder().encode(bookmark)
        )
        #expect(restored == bookmark)
    }

    /// The id is what the frecency history and the list's selection are keyed
    /// by, so it cannot be the name — renaming a bookmark would otherwise
    /// throw away everything Pium had learned about it.
    @Test func twoBookmarksOfTheSameNameAreStillTwoBookmarks() {
        let one = Bookmark(name: "Notes", destination: .path("~/a.md"))
        let other = Bookmark(name: "Notes", destination: .path("~/a.md"))
        #expect(one.id != other.id)
    }
}
