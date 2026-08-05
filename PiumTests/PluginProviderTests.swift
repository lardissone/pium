import Testing
import Foundation
@testable import Pium

@Suite("Plugin provider")
@MainActor
struct PluginProviderTests {
    private func manifest(
        id: String,
        name: String,
        aliases: [String] = [],
        keywords: [String] = [],
        inputMode: PluginInputMode = .none,
        placeholder: String? = nil,
        icon: String? = nil
    ) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1,
            id: id,
            name: name,
            description: nil,
            keywords: keywords,
            aliases: aliases,
            icon: icon,
            input: PluginInput(mode: inputMode, placeholder: placeholder),
            command: PluginCommand(executable: "true", arguments: [], workingDirectory: nil),
            configuration: [],
            output: PluginOutput(mode: .silent),
            timeoutSeconds: nil,
            confirmBeforeRun: nil
        )
    }

    private func provider(_ records: [PluginRecord]) -> PluginProvider {
        let index = PluginIndex(
            root: URL(filePath: "/tmp/unused"),
            loader: { _ in records },
            watcher: NullWatcher()
        )
        index.refresh()
        return PluginProvider(index: index, reveal: { _ in })
    }

    private func valid(_ manifest: PluginManifest) -> PluginRecord {
        PluginRecord(
            fileURL: URL(filePath: "/tmp/\(manifest.id).pium.json"),
            manifest: manifest,
            diagnostic: nil
        )
    }

    private func results(
        _ provider: PluginProvider,
        _ query: String
    ) async -> [SearchResult] {
        var last: [SearchResult] = []
        for await batch in provider.results(for: TextNormalizer.query(query)) { last = batch }
        return last
    }

    @Test func thekindIsPlugin() {
        #expect(provider([]).kind == .plugin)
    }

    @Test func anEmptyQueryMatchesNothing() async {
        let provider = provider([valid(manifest(id: "web.yt", name: "YouTube"))])
        #expect(await results(provider, "").isEmpty)
    }

    @Test func thenameMatches() async {
        let provider = provider([valid(manifest(id: "web.yt", name: "YouTube"))])
        #expect(await results(provider, "yout").map(\.title) == ["YouTube"])
    }

    /// An alias is an explicit trigger, so it must match as strongly as a name.
    @Test func analiasMatches() async {
        let provider = provider([
            valid(manifest(id: "web.yt", name: "YouTube", aliases: ["yt"]))
        ])
        #expect(await results(provider, "yt").map(\.title) == ["YouTube"])
    }

    @Test func akeywordMatches() async {
        let provider = provider([
            valid(manifest(id: "web.yt", name: "YouTube", keywords: ["video"]))
        ])
        #expect(await results(provider, "video").map(\.title) == ["YouTube"])
    }

    @Test func somethingUnrelatedDoesNotMatch() async {
        let provider = provider([valid(manifest(id: "web.yt", name: "YouTube"))])
        #expect(await results(provider, "zzzz").isEmpty)
    }

    /// Execution is Phase 5, so the only thing a plugin row can do is show the
    /// author their file. A row that looks runnable and is not would be a lie.
    @Test func apluginResultOnlyOffersReveal() async throws {
        let provider = provider([valid(manifest(id: "web.yt", name: "YouTube"))])
        let result = try #require(await results(provider, "yout").first)
        #expect(result.actions.map(\.id) == ["reveal"])
        #expect(result.actions.first?.shortcut == .returnKey)
    }

    @Test func apluginThatTakesInputCarriesAnArgumentRequest() async throws {
        let provider = provider([
            valid(manifest(
                id: "web.yt", name: "YouTube", inputMode: .required, placeholder: "Search terms"
            ))
        ])
        let result = try #require(await results(provider, "yout").first)
        #expect(result.argument?.isRequired == true)
        #expect(result.argument?.placeholder == "Search terms")
    }

    @Test func apluginThatTakesNoInputCarriesNoArgumentRequest() async throws {
        let provider = provider([valid(manifest(id: "web.yt", name: "YouTube"))])
        #expect(try #require(await results(provider, "yout").first).argument == nil)
    }

    @Test func anOptionalInputIsNotRequired() async throws {
        let provider = provider([
            valid(manifest(id: "web.yt", name: "YouTube", inputMode: .optional))
        ])
        #expect(try #require(await results(provider, "yout").first).argument?.isRequired == false)
    }

    /// The Plugins section of Preferences is 4b, so a broken manifest surfaces
    /// where the user already is. Silence would leave them with a plugin that
    /// simply never appears and no way to find out why.
    @Test func aninvalidPluginAppearsAsAnErrorRow() async throws {
        let provider = provider([
            PluginRecord(
                fileURL: URL(filePath: "/tmp/broken.pium.json"),
                manifest: nil,
                diagnostic: .unknownKey(path: "command", key: "shel")
            )
        ])
        let result = try #require(await results(provider, "broken").first)
        #expect(result.subtitle?.contains("shel") == true)
        #expect(result.actions.map(\.id) == ["reveal"])
        // A warning symbol rather than an ordinary one, so the row can be
        // coloured without the view guessing from the symbol's name.
        guard case .warningSymbol = result.iconSource else {
            Issue.record("A broken plugin must be marked as a warning")
            return
        }
    }

    /// An invalid file has no name, so it is found by its filename — the only
    /// thing the author knows it by.
    @Test func anInvalidPluginIsFoundByItsFileName() async {
        let provider = provider([
            PluginRecord(
                fileURL: URL(filePath: "/tmp/youtube.pium.json"),
                manifest: nil,
                diagnostic: .unreadableFile
            )
        ])
        #expect(await !results(provider, "youtube").isEmpty)
    }

    /// An unknown SF Symbol falls back and the plugin still works — PIUM-DOC-2
    /// §5 makes the symbol a runtime concern, not a validation one.
    @Test func anUnknownSymbolFallsBackWithoutInvalidatingThePlugin() async throws {
        let provider = provider([
            valid(manifest(id: "web.yt", name: "YouTube", icon: "not.a.real.symbol"))
        ])
        let result = try #require(await results(provider, "yout").first)
        #expect(result.iconSource == .systemSymbol(PluginProvider.fallbackSymbol))
    }

    @Test func aknownSymbolIsUsed() async throws {
        let provider = provider([
            valid(manifest(id: "web.yt", name: "YouTube", icon: "play.rectangle.fill"))
        ])
        let result = try #require(await results(provider, "yout").first)
        #expect(result.iconSource == .systemSymbol("play.rectangle.fill"))
    }

    @Test func resultsAreOrderedByDescendingScore() async {
        let provider = provider([
            valid(manifest(id: "a.one", name: "Yo")),
            valid(manifest(id: "b.two", name: "YouTube")),
        ])
        #expect(await results(provider, "yo").first?.title == "Yo")
    }
}

@MainActor
private final class NullWatcher: PluginDirectoryWatching {
    func start(root: URL, onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}
