import Testing
import Foundation
import AppKit
@testable import Pium

/// A one-pixel PNG, so a test can hand the store something `NSImage` will
/// actually decode without shipping a fixture file.
private let pixelPNG = Data(base64Encoded: """
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
""")!

@Suite("Fetching a site's icon")
@MainActor
struct FaviconStoreTests {
    /// Counts what was asked of the network, and answers with whatever the
    /// test decided this host should return.
    @MainActor
    final class Network {
        var answers: [String: Data] = [:]
        private(set) var requested: [URL] = []
        var onRequest: (@MainActor () async -> Void)?

        func fetch(_ url: URL) async -> Data? {
            requested.append(url)
            await onRequest?()
            return answers[url.absoluteString]
        }
    }

    private func makeStore(
        _ network: Network,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> (FaviconStore, URL) {
        let directory = URL.temporaryDirectory.appending(path: "pium-favicons-\(UUID().uuidString)")
        let store = FaviconStore(
            directory: directory,
            fetch: { url in await network.fetch(url) },
            now: now
        )
        return (store, directory)
    }

    @Test func anIconIsAskedForOnceAndKept() async throws {
        let network = Network()
        network.answers["https://example.com/favicon.ico"] = pixelPNG
        let (store, directory) = makeStore(network)
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.fetchIfNeeded(host: "example.com")
        await store.fetchIfNeeded(host: "example.com")

        #expect(network.requested.count == 1)
        #expect(store.icon(forHost: "example.com") != nil)
    }

    /// A second store over the same directory is what a relaunch is: the icon
    /// is on disk, so nothing is asked for again.
    @Test func anIconOnDiskSurvivesArelaunch() async throws {
        let network = Network()
        network.answers["https://example.com/favicon.ico"] = pixelPNG
        let (store, directory) = makeStore(network)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.fetchIfNeeded(host: "example.com")

        let second = FaviconStore(directory: directory, fetch: { _ in nil })

        #expect(second.icon(forHost: "example.com") != nil)
    }

    /// `/favicon.ico` is the cheap guess and it is wrong often enough to need a
    /// second try: the page itself says where its icon is.
    @Test func apageIsReadForItsIconWhenTheCheapGuessFails() async throws {
        let network = Network()
        network.answers["https://example.com/"] = Data("""
        <html><head><link rel="icon" href="/assets/icon-32.png"></head></html>
        """.utf8)
        network.answers["https://example.com/assets/icon-32.png"] = pixelPNG
        let (store, directory) = makeStore(network)
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.fetchIfNeeded(host: "example.com")

        #expect(store.icon(forHost: "example.com") != nil)
        #expect(network.requested.map(\.path) == ["/favicon.ico", "/", "/assets/icon-32.png"])
    }

    /// Held in memory only, so the next launch tries again — but not on every
    /// keystroke in this one.
    @Test func afailureIsNotRetriedUntilTheCooldownHasPassed() async throws {
        let network = Network()
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let (store, directory) = makeStore(network, now: { clock.date })
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.fetchIfNeeded(host: "example.com")
        let afterFirst = network.requested.count
        await store.fetchIfNeeded(host: "example.com")
        #expect(network.requested.count == afterFirst, "a failure inside the cooldown asks nothing")

        clock.date = clock.date.addingTimeInterval(FaviconStore.cooldown + 1)
        await store.fetchIfNeeded(host: "example.com")
        #expect(network.requested.count > afterFirst, "past the cooldown it tries again")
    }

    /// Two rows for the same host render in the same breath. One question.
    @Test func onlyOneFetchPerHostIsInFlightAtOnce() async throws {
        let network = Network()
        network.answers["https://example.com/favicon.ico"] = pixelPNG
        let (store, directory) = makeStore(network)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Held open until both callers are inside, so the second cannot simply
        // be arriving after the first has finished.
        let gate = Gate()
        network.onRequest = { await gate.wait() }

        async let first: Void = store.fetchIfNeeded(host: "example.com")
        async let second: Void = store.fetchIfNeeded(host: "example.com")
        await gate.open()
        _ = await (first, second)

        #expect(network.requested.count == 1)
    }

    /// An icon is small. Anything that is not is somebody else's problem being
    /// downloaded into Pium's cache directory.
    @Test func somethingTooLargeIsNotAnIcon() async throws {
        let network = Network()
        network.answers["https://example.com/favicon.ico"] =
            Data(repeating: 0, count: FaviconStore.maximumBytes + 1)
        let (store, directory) = makeStore(network)
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.fetchIfNeeded(host: "example.com")

        #expect(store.icon(forHost: "example.com") == nil)
    }

    @Test func somethingThatIsNotAnImageIsNotAnIcon() async throws {
        let network = Network()
        network.answers["https://example.com/favicon.ico"] = Data("<html>404</html>".utf8)
        network.answers["https://example.com/"] = Data("<html><head></head></html>".utf8)
        let (store, directory) = makeStore(network)
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.fetchIfNeeded(host: "example.com")

        #expect(store.icon(forHost: "example.com") == nil)
    }
}

/// A clock a test can wind forward, readable from the store's `@Sendable`
/// closure. Unchecked because these tests drive it from one thread and the
/// alternative is a lock guarding a `Date` nobody races for.
private final class Clock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

/// Lets a test hold a fetch open until it says otherwise.
private actor Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}

/// The one test that uses the network Pium actually talks to.
///
/// Everything above injects a fetcher, which proves the bookkeeping and proves
/// nothing about `URLSession`, the status-code check, or the timeout — the
/// parts that decide whether any of this works on a real Mac. Skipped on CI,
/// where a runner's network is not a promise worth failing a build over.
@Suite("Asking a real site", .disabled(if: isRunningOnCI))
@MainActor
struct FaviconNetworkTests {
    @Test func awellKnownSiteAnswersWithSomethingThatDecodes() async throws {
        let directory = URL.temporaryDirectory.appending(path: "pium-favicons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        // The default fetcher, deliberately: this is the code path no other
        // test in this file reaches.
        let store = FaviconStore(directory: directory)
        await store.fetchIfNeeded(host: "github.com")

        #expect(
            store.icon(forHost: "github.com") != nil,
            "github.com has a favicon; if this fails, check the network before the code"
        )
    }
}

@Suite("Reading a page for its icon")
struct FaviconHTMLTests {
    @Test func alinkTagNamesTheIcon() {
        #expect(
            FaviconStore.iconHref(inHTML: #"<link rel="icon" href="/a/icon.png">"#) == "/a/icon.png"
        )
        #expect(
            FaviconStore.iconHref(inHTML: #"<link rel='shortcut icon' href='/i.ico'>"#) == "/i.ico"
        )
        #expect(
            FaviconStore.iconHref(inHTML: #"<link href="/t.png" rel="apple-touch-icon">"#) == "/t.png"
        )
    }

    @Test func apageWithoutOneSaysSo() {
        #expect(FaviconStore.iconHref(inHTML: "<html><head><title>x</title></head>") == nil)
        #expect(FaviconStore.iconHref(inHTML: #"<link rel="stylesheet" href="/a.css">"#) == nil)
    }
}
