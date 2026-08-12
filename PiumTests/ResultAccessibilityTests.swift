import Testing
import Foundation
@testable import Pium

@Suite("Result accessibility")
struct ResultAccessibilityTests {
    private func result(
        _ title: String,
        kind: ResultKind,
        subtitle: String? = nil
    ) -> SearchResult {
        SearchResult(
            id: "\(kind.rawValue):\(title)",
            kind: kind,
            title: title,
            subtitle: subtitle,
            iconSource: .systemSymbol("app"),
            searchableTerms: [title],
            textScore: 1,
            actions: []
        )
    }

    /// The icon is what tells a sighted user whether "Notes" is the app, a
    /// file, or a plugin, and it is hidden from VoiceOver as decoration. The
    /// kind has to be said in words or the distinction is simply lost.
    @Test func adescriptionNamesTheKindTheIconStandsFor() {
        #expect(result("Notes", kind: .application).accessibilityDescription.contains("Notes"))
        for kind in ResultKind.allCases {
            let described = result("Notes", kind: kind).accessibilityDescription
            #expect(
                described != "Notes",
                "\(kind.rawValue) reads the same as every other kind"
            )
            #expect(!described.contains("result.kind."), "untranslated: \(described)")
        }
    }

    @Test func everyKindReadsDifferently() {
        let descriptions = ResultKind.allCases.map {
            result("Notes", kind: $0).accessibilityDescription
        }
        #expect(Set(descriptions).count == ResultKind.allCases.count)
    }

    /// A file's subtitle is its folder, which is the only thing separating two
    /// results with the same name.
    @Test func asubtitleIsKeptWhenThereIsOne() {
        let described = result("report.pdf", kind: .file, subtitle: "~/Documents")
            .accessibilityDescription
        #expect(described.contains("report.pdf"))
        #expect(described.contains("~/Documents"))
    }

    @Test func nosubtitleLeavesNoDanglingPunctuation() {
        let described = result("Notes", kind: .application).accessibilityDescription
        #expect(!described.hasSuffix(","))
        #expect(!described.contains(", ,"))
    }
}
