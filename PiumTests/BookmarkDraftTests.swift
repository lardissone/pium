import Testing
import Foundation
@testable import Pium

@Suite("Filling in a bookmark")
struct BookmarkDraftTests {
    private func draft(
        name: String = "Notes",
        destination: String = "https://example.com",
        keywords: String = "",
        openWith: String? = nil
    ) -> BookmarkDraft {
        BookmarkDraft(name: name, destination: destination, keywords: keywords, openWith: openWith)
    }

    @Test func afilledFormBecomesAbookmark() throws {
        let id = UUID()
        let bookmark = try draft(
            name: "  Home Assistant  ",
            destination: "  https://home.local  ",
            keywords: "hass, casa",
            openWith: "com.google.Chrome"
        ).bookmark(id: id).get()

        #expect(bookmark.id == id)
        #expect(bookmark.name == "Home Assistant")
        #expect(bookmark.destination == .link("https://home.local"))
        #expect(bookmark.keywords == ["hass", "casa"])
        #expect(bookmark.openWith == "com.google.Chrome")
    }

    /// One field, comma separated, because a person adding two aliases should
    /// not have to meet a list editor to do it.
    @Test func keywordsAreSplitTidiedAndEmptiesDropped() throws {
        let bookmark = try draft(keywords: " hass , , casa ,").bookmark(id: UUID()).get()

        #expect(bookmark.keywords == ["hass", "casa"])
    }

    @Test func anameOfNothingIsRefused() {
        #expect(draft(name: "").bookmark(id: UUID()).failure == .nameIsEmpty)
        #expect(draft(name: "   ").bookmark(id: UUID()).failure == .nameIsEmpty)
    }

    /// The destination's own reasons, carried through rather than flattened
    /// into one "invalid" — the form says which of them beside the field.
    @Test func adestinationCarriesItsOwnReasonForBeingRefused() {
        #expect(
            draft(destination: "").bookmark(id: UUID()).failure == .destination(.empty)
        )
        #expect(
            draft(destination: "example.com").bookmark(id: UUID()).failure
                == .destination(.unrecognized("example.com"))
        )
        #expect(
            draft(destination: "https://x.com/{{input").bookmark(id: UUID()).failure
                == .destination(.invalidTemplate(.unclosedPlaceholder("https://x.com/{{input")))
        )
    }

    /// Editing an existing bookmark starts from what it holds, so opening the
    /// form and saving it again changes nothing.
    @Test func abookmarkOpensIntoAformAndComesBackTheSame() throws {
        let original = Bookmark(
            name: "Home Assistant",
            destination: .link("https://home.local"),
            keywords: ["hass", "casa"],
            openWith: "com.google.Chrome"
        )

        let restored = try BookmarkDraft(original).bookmark(id: original.id).get()

        #expect(restored == original)
    }

    /// What the line under the destination field says while it is being typed.
    /// Structured rather than a sentence, so the wording stays in the view and
    /// the decision stays testable.
    @Test func theFormSaysHowItReadWhatWasTyped() {
        #expect(draft(destination: "").reading == .empty)
        #expect(draft(destination: "   ").reading == .empty)
        #expect(draft(destination: "https://x.com").reading == .link(takesArgument: false))
        #expect(
            draft(destination: "https://x.com/?q={{input}}").reading == .link(takesArgument: true)
        )
        #expect(draft(destination: "~/Documents").reading == .path(takesArgument: false))
        #expect(
            draft(destination: "~/Documents/{{input}}.pdf").reading == .path(takesArgument: true)
        )
        #expect(draft(destination: "example.com").reading == .unreadable)
        #expect(draft(destination: "https://x.com/{{input").reading == .unreadable)
    }
}
