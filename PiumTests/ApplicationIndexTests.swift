import Testing
import Foundation
@testable import Pium

@Suite("Application index")
@MainActor
struct ApplicationIndexTests {
    /// Nonisolated so the `@Sendable` scanner closures can build fixtures.
    private nonisolated func app(_ name: String) -> InstalledApplication {
        InstalledApplication(
            name: name,
            bundleURL: URL(filePath: "/Applications/\(name).app"),
            bundleIdentifier: "test.\(name.lowercased())"
        )
    }

    @Test func theIndexIsEmptyUntilRefreshed() {
        let index = ApplicationIndex(roots: []) { _ in [self.app("Safari")] }
        #expect(index.applications.isEmpty)
    }

    @Test func refreshPopulatesFromTheScanner() {
        let index = ApplicationIndex(roots: []) { _ in [self.app("Safari"), self.app("Mail")] }
        index.refresh()
        #expect(index.applications.map(\.name) == ["Safari", "Mail"])
    }

    /// An application installed or removed after launch must show up without a
    /// restart, which is what the observer exists for.
    @Test func refreshReplacesThePreviousSnapshot() {
        /// Holds what is "installed" by reference, so the scanner closure sees
        /// changes made after it was captured.
        final class Installed: @unchecked Sendable {
            var applications: [InstalledApplication] = []
        }

        let installed = Installed()
        installed.applications = [app("Safari")]
        let index = ApplicationIndex(roots: []) { _ in installed.applications }

        index.refresh()
        #expect(index.applications.count == 1)

        installed.applications.append(app("Mail"))
        index.refresh()
        #expect(index.applications.count == 2)
    }

    /// Queries read the snapshot synchronously, so a scan must never happen on
    /// the query path.
    @Test func readingApplicationsDoesNotRescan() {
        nonisolated(unsafe) var scanCount = 0
        let index = ApplicationIndex(roots: []) { _ in
            scanCount += 1
            return []
        }
        index.refresh()
        _ = index.applications
        _ = index.applications
        #expect(scanCount == 1)
    }
}
