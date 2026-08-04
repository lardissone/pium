import Testing
import Foundation
@testable import Pium

@Suite("Application provider")
@MainActor
struct ApplicationProviderTests {
    private func makeProvider(
        _ names: [String],
        opened: @escaping @Sendable @MainActor (URL) -> Void = { _ in }
    ) -> ApplicationProvider {
        let apps = names.map {
            InstalledApplication(
                name: $0,
                bundleURL: URL(filePath: "/Applications/\($0).app"),
                bundleIdentifier: "test.\($0.lowercased())"
            )
        }
        let index = ApplicationIndex(roots: []) { _ in apps }
        index.refresh()
        return ApplicationProvider(index: index, open: opened, reveal: { _ in })
    }

    @Test func matchingApplicationsAreReturned() async {
        let provider = makeProvider(["Safari", "Mail", "Calendar"])
        let results = await provider.results(for: TextNormalizer.query("saf"))
        #expect(results.map(\.title) == ["Safari"])
    }

    /// The text gate: an unrelated query returns nothing at all.
    @Test func unrelatedQueriesReturnNothing() async {
        let provider = makeProvider(["Safari", "Mail"])
        let results = await provider.results(for: TextNormalizer.query("zzzzz"))
        #expect(results.isEmpty)
    }

    /// The launcher shows nothing until the user types.
    @Test func anEmptyQueryReturnsNothing() async {
        let provider = makeProvider(["Safari"])
        let results = await provider.results(for: TextNormalizer.query(""))
        #expect(results.isEmpty)
    }

    @Test func resultsAreSortedByDescendingScore() async {
        let provider = makeProvider(["MailMate", "Mail"])
        let results = await provider.results(for: TextNormalizer.query("mail"))
        #expect(results.map(\.title) == ["Mail", "MailMate"])
    }

    @Test func everyResultIsAnApplicationWithAStableIdentity() async {
        let provider = makeProvider(["Safari"])
        let results = await provider.results(for: TextNormalizer.query("safari"))
        #expect(results.first?.kind == .application)
        #expect(results.first?.id == "/Applications/Safari.app")
    }

    /// Open first, then Reveal — the order the PRD fixes, and the first is what
    /// `Return` runs.
    @Test func resultsCarryOpenThenRevealActions() async {
        let provider = makeProvider(["Safari"])
        let results = await provider.results(for: TextNormalizer.query("safari"))
        #expect(results.first?.actions.map(\.id) == ["open", "reveal"])
    }

    /// The action must open the bundle it belongs to, which is the whole point.
    @Test func theOpenActionOpensThatApplication() async {
        nonisolated(unsafe) var opened: URL?
        let provider = makeProvider(["Safari"]) { opened = $0 }
        let results = await provider.results(for: TextNormalizer.query("safari"))
        results.first?.primaryAction?.perform()
        #expect(opened?.path == "/Applications/Safari.app")
    }
}
