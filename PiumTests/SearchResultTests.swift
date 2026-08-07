import Testing
@testable import Pium

@Suite("Result model")
struct SearchResultTests {
    /// The PRD fixes the tie-break order as plugin, application, file. Encoding
    /// it on the kind keeps every future ranker honest.
    @Test func tieBreakOrderIsPluginThenApplicationThenFile() {
        #expect(ResultKind.plugin.tieBreakRank < ResultKind.application.tieBreakRank)
        #expect(ResultKind.application.tieBreakRank < ResultKind.file.tieBreakRank)
    }

    @Test func everyKindHasADistinctRank() {
        let ranks = ResultKind.allCases.map(\.tieBreakRank)
        #expect(Set(ranks).count == ranks.count)
    }

    /// The first action is the one `Return` runs; the rest populate the
    /// contextual menu.
    @Test func primaryActionIsTheFirstAction() {
        let open = ResultAction(id: "open", title: "Open") { _ in }
        let reveal = ResultAction(id: "reveal", title: "Reveal in Finder") { _ in }
        let result = SearchResult(
            id: "app:/Applications/Safari.app",
            kind: .application,
            title: "Safari",
            subtitle: nil,
            iconSource: .systemSymbol("app"),
            searchableTerms: ["Safari"],
            textScore: 1,
            actions: [open, reveal]
        )
        #expect(result.primaryAction?.id == "open")
    }

    @Test func aResultWithNoActionsHasNoPrimaryAction() {
        let result = SearchResult(
            id: "x",
            kind: .file,
            title: "x",
            subtitle: nil,
            iconSource: .systemSymbol("doc"),
            searchableTerms: [],
            textScore: 0,
            actions: []
        )
        #expect(result.primaryAction == nil)
    }
}
