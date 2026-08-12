import Testing
import Foundation
@testable import Pium

/// Measures what `docs/measuring-latency.md` calls the headless route: driving
/// `SearchCoordinator` directly against the real index, in an optimised build,
/// with nobody at the keyboard.
///
/// Off unless `PIUM_MEASURE=1`, for two reasons. It is slow — dozens of real
/// searches over every application installed on the machine — and its numbers
/// mean nothing in a Debug build, which is what every other run of this suite
/// is. The scheme forwards the variable the same way it forwards `CI`.
///
/// It asserts nothing about the numbers. A budget enforced here would fail on
/// whatever else the machine happened to be doing; the figures are read by a
/// person and written into the document's table, where a regression is
/// investigated rather than declared.
@Suite("Search latency", .enabled(if: ProcessInfo.processInfo.environment["PIUM_MEASURE"] == "1"))
@MainActor
struct SearchLatencyMeasurementTests {
    /// One- and two-character queries, which is where the budget bites: they
    /// match the most and rank the most.
    private static let queries = [
        "a", "s", "c", "m", "p", "t", "f", "n",
        "sa", "ch", "fi", "no", "ma", "te", "pr", "do",
    ]

    /// Enough samples for a p95 to mean something, matching the 32 the earlier
    /// figures in the document were taken over: three passes of sixteen
    /// queries, less the cold one.
    private static let passes = 3

    private func measure(
        _ coordinator: SearchCoordinator,
        label: String
    ) async -> [Duration] {
        var samples: [Duration] = []
        for pass in 0..<Self.passes {
            for query in Self.queries {
                let started = ContinuousClock.now
                for await _ in coordinator.search(query) {}
                let elapsed = ContinuousClock.now - started
                // The first pass is cold: caches, the index's first read, and
                // whatever the runtime lazily sets up on the way through.
                if pass > 0 { samples.append(elapsed) }
            }
        }
        report(samples, label: label)
        return samples
    }

    private func report(_ samples: [Duration], label: String) {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return }
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let median = sorted[sorted.count / 2]
        print(
            """

            === \(label) ===
            samples: \(sorted.count)
            median:  \(milliseconds(median)) ms
            p95:     \(milliseconds(p95)) ms
            slowest: \(milliseconds(sorted[sorted.count - 1])) ms

            """
        )
    }

    private func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1_000 + Double(attoseconds) / 1_000_000_000_000_000
        return String(format: "%.2f", value)
    }

    private func frecency() -> FrecencyStore {
        FrecencyStore(fileURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    }

    @Test func applications() async {
        let index = ApplicationIndex()
        // Synchronous: `refresh` assigns what the scanner returns, so there is
        // nothing to wait for and a sleep here would only pad the run.
        index.refresh()
        print("applications indexed: \(index.applications.count)")

        let coordinator = SearchCoordinator(
            providers: [ApplicationProvider(index: index)], frecency: frecency()
        )
        let samples = await measure(coordinator, label: "Applications")
        #expect(!samples.isEmpty)
    }

    @Test func plugins() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A folder larger than anyone's, so the figure is an upper bound
        // rather than a description of one particular machine.
        for number in 0..<50 {
            let manifest = """
            {
              "schemaVersion": 1,
              "id": "demo.probe\(number)",
              "name": "Probe \(number)",
              "keywords": ["sample", "test", "probe"],
              "input": { "mode": "none" },
              "command": { "executable": "echo", "arguments": ["\(number)"] },
              "output": { "mode": "silent" }
            }
            """
            try manifest.write(
                to: root.appending(path: "probe\(number).pium.json"),
                atomically: true,
                encoding: .utf8
            )
        }

        let index = PluginIndex(root: root)
        index.refresh()
        print("plugins indexed: \(index.records.count)")

        let coordinator = SearchCoordinator(
            providers: [
                PluginProvider(
                    index: index,
                    status: {
                        PluginStatusResolver(
                            configuration: PluginConfigurationStore(
                                defaults: UserDefaults(suiteName: UUID().uuidString)!
                            ),
                            secrets: InMemorySecretStore(secrets: [:]),
                            disabledIDs: []
                        )
                    },
                    execute: { _, _ in }
                )
            ],
            frecency: frecency()
        )
        let samples = await measure(coordinator, label: "Plugins")
        #expect(!samples.isEmpty)
    }
}
