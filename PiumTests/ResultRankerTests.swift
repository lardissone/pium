import Testing
import Foundation
@testable import Pium

@Suite("Result ranking")
struct ResultRankerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func result(
        _ title: String,
        kind: ResultKind,
        score: Double
    ) -> SearchResult {
        SearchResult(
            id: "\(kind.rawValue):\(title)",
            kind: kind,
            title: title,
            subtitle: nil,
            iconSource: .systemSymbol("doc"),
            searchableTerms: [title],
            textScore: score,
            actions: []
        )
    }

    /// A bookmark is the only result the user made by hand, with a name they
    /// chose, so an equal text score means it is what they meant.
    @Test func abookmarkOutranksEverythingElseOnAnEqualScore() {
        let ranked = ResultRanker.rank(
            [
                result("Notes", kind: .file, score: 0.9),
                result("Notes", kind: .application, score: 0.9),
                result("Notes", kind: .plugin, score: 0.9),
                result("Notes", kind: .bookmark, score: 0.9),
            ],
            for: TextNormalizer.query("notes"),
            usage: UsageSnapshot(entries: []),
            now: now
        )

        #expect(ranked.map(\.kind) == [.bookmark, .plugin, .application, .file])
    }

    private func files(_ count: Int, score: Double = 0.5) -> [SearchResult] {
        (0..<count).map { result("file\($0)", kind: .file, score: score) }
    }

    private func applications(_ count: Int, score: Double = 0.5) -> [SearchResult] {
        (0..<count).map { result("App\($0)", kind: .application, score: score) }
    }

    private func rank(
        _ results: [SearchResult],
        _ query: String = "x",
        usage: UsageSnapshot = UsageSnapshot(entries: [])
    ) -> [SearchResult] {
        ResultRanker.rank(
            results,
            for: TextNormalizer.query(query),
            usage: usage,
            now: now
        )
    }

    @Test func higherTextScoreComesFirst() {
        let ranked = rank([
            result("Low", kind: .application, score: 0.4),
            result("High", kind: .application, score: 0.9),
        ])
        #expect(ranked.map(\.title) == ["High", "Low"])
    }

    /// The PRD fixes the tie-break as plugin, application, file.
    @Test func equalScoresBreakTowardPluginThenApplicationThenFile() {
        let ranked = rank([
            result("F", kind: .file, score: 0.5),
            result("A", kind: .application, score: 0.5),
            result("P", kind: .plugin, score: 0.5),
        ])
        #expect(ranked.map(\.title) == ["P", "A", "F"])
    }

    /// Usage reorders what the matcher considered equal.
    @Test func aPreviouslySelectedResultOvertakesAnEqualOne() {
        let usage = UsageSnapshot(entries: [
            FrecencyEntry(
                resultID: "application:Used", query: "x", selectionCount: 5, lastSelected: now
            )
        ])
        let ranked = rank([
            result("Fresh", kind: .application, score: 0.5),
            result("Used", kind: .application, score: 0.5),
        ], usage: usage)
        #expect(ranked.map(\.title) == ["Used", "Fresh"])
    }

    /// The gate is the matcher's, not the ranker's: a strong text match still
    /// beats a weak one that happens to be familiar, because the boost is
    /// bounded.
    @Test func usageCannotOvertakeAMuchStrongerTextMatch() {
        let usage = UsageSnapshot(entries: [
            FrecencyEntry(
                resultID: "application:Familiar",
                query: "x",
                selectionCount: 1000,
                lastSelected: now
            )
        ])
        let ranked = rank([
            result("Exact", kind: .application, score: 1.0),
            result("Familiar", kind: .application, score: 0.2),
        ], usage: usage)
        #expect(ranked.first?.title == "Exact")
    }

    /// Files must not fill the first screen and push applications off it.
    ///
    /// Five applications, because the quota can only hold files back as far as
    /// there is other content to hold them back *with*: among twenty files and
    /// one application, nine of the first ten rows are files however they are
    /// ordered. The guarantee for that case is the test below.
    @Test func filesAreCappedInsideTheLeadingWindow() {
        let ranked = rank(files(20, score: 0.9) + applications(5, score: 0.5))
        let leading = ranked.prefix(ResultRanker.leadingWindow)
        #expect(leading.filter { $0.kind == .file }.count <= ResultRanker.maximumFilesInLeadingWindow)
        #expect(leading.filter { $0.kind == .application }.count == 4)
    }

    /// The user-facing half of the quota: however many files match, the
    /// application the user is probably after stays on the first screen.
    @Test func theLeadingWindowKeepsAnApplicationVisible() {
        let ranked = rank(files(20, score: 0.9) + [result("App", kind: .application, score: 0.5)])
        #expect(ranked.prefix(ResultRanker.leadingWindow).contains { $0.kind == .application })
    }

    /// A quota moves surplus files down; it does not delete them. The user can
    /// still scroll to every match.
    @Test func surplusFilesAreMovedNotDropped() {
        let input = files(20, score: 0.9) + [result("App", kind: .application, score: 0.5)]
        #expect(rank(input).count == input.count)
    }

    /// With few files there is nothing to move, and the order stays purely by
    /// score.
    @Test func theQuotaDoesNothingWhenFilesAreScarce() {
        let ranked = rank([
            result("file0", kind: .file, score: 0.9),
            result("App", kind: .application, score: 0.5),
        ])
        #expect(ranked.map(\.title) == ["file0", "App"])
    }

    @Test func anEmptyListRanksToAnEmptyList() {
        #expect(rank([]).isEmpty)
    }
}
