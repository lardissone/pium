import Testing
import Foundation
@testable import Pium

/// Real events against a real directory. The unit tests in `PluginIndexTests`
/// prove the index's logic with a hand-driven watcher; this proves the watcher
/// itself, which is where the platform bugs live.
@Suite("Filesystem event watcher")
@MainActor
struct FileSystemEventWatcherTests {
    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Polls `condition` rather than sleeping a fixed time: FSEvents latency
    /// varies and a fixed sleep is either slow or flaky. Shared by every test
    /// in this suite that waits for the watcher to report something.
    private func poll(until condition: () -> Bool, timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func awaitChange(
        _ watcher: FileSystemEventWatcher,
        root: URL,
        timeout: Duration = .seconds(10),
        whileDoing work: () throws -> Void
    ) async rethrows -> Bool {
        var fired = false
        watcher.start(root: root) { fired = true }
        defer { watcher.stop() }

        try work()

        await poll(until: { fired }, timeout: timeout)
        return fired
    }

    @Test func creatingAFileIsReported() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fired = try await awaitChange(
            FileSystemEventWatcher(debounce: .milliseconds(50)), root: root
        ) {
            try "{}".write(
                to: root.appending(path: "a.pium.json"), atomically: true, encoding: .utf8
            )
        }
        #expect(fired, "Creating a manifest must be reported")
    }

    /// The case a directory vnode source misses, and the reason this is FSEvents.
    @Test func editingAnExistingFileInPlaceIsReported() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "a.pium.json")
        try "{}".write(to: file, atomically: true, encoding: .utf8)

        let fired = try await awaitChange(
            FileSystemEventWatcher(debounce: .milliseconds(50)), root: root
        ) {
            // Appending through a handle rather than an atomic write, because an
            // atomic write replaces the file and would change the directory too.
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(" ".utf8))
        }
        #expect(fired, "Editing a manifest in place must be reported")
    }

    @Test func stoppingEndsTheReports() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var fired = false
        let watcher = FileSystemEventWatcher(debounce: .milliseconds(50))
        watcher.start(root: root) { fired = true }
        watcher.stop()

        try "{}".write(
            to: root.appending(path: "a.pium.json"), atomically: true, encoding: .utf8
        )
        try? await Task.sleep(for: .seconds(2))
        #expect(!fired, "A stopped watcher must report nothing")
    }

    /// A burst of writes is one reload, or saving a file in an editor that
    /// writes in chunks would reparse the folder several times.
    ///
    /// PIUM-105: a fixed sleep before asserting was flaky on a loaded CI
    /// runner, where FSEvents had not reported yet when the assertion ran.
    /// This waits for the first report the way every other test in this
    /// suite does, then gives a trailing FSEvents batch room to land — the
    /// ten writes can arrive as more than one batch, each restarting the
    /// debounce timer — before counting.
    @Test func aburstOfChangesIsCoalescedIntoOneReport() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var count = 0
        let debounce = Duration.milliseconds(300)
        let watcher = FileSystemEventWatcher(debounce: debounce)
        watcher.start(root: root) { count += 1 }
        defer { watcher.stop() }

        for index in 0..<10 {
            try "{}".write(
                to: root.appending(path: "\(index).pium.json"),
                atomically: true,
                encoding: .utf8
            )
        }

        await poll(until: { count >= 1 }, timeout: .seconds(10))
        let firstReportCount = count
        let expectedMinimumReports = 1
        #expect(firstReportCount >= expectedMinimumReports, "The burst must be reported")

        try? await Task.sleep(for: debounce * 3)
        let settledCount = count
        let expectedMaximumReports = 3
        #expect(
            settledCount <= expectedMaximumReports,
            "Ten writes must not become ten reloads, got \(settledCount)"
        )
    }
}
