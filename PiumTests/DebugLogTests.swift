import Testing
import Foundation
@testable import Pium

@Suite("Debug log facade")
@MainActor
struct DebugLogTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Restores the shared seams, so one test cannot leave the next one
    /// writing into its directory.
    private func withFacade(
        expiry: Date?,
        directory: URL,
        _ body: (Preferences) async throws -> Void
    ) async rethrows {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.debugLoggingExpiry = expiry
        let previousStore = DebugLog.store
        let previousPreferences = DebugLog.preferences
        DebugLog.store = DebugLogStore(directory: directory, now: { Date() })
        DebugLog.preferences = preferences
        defer {
            DebugLog.store = previousStore
            DebugLog.preferences = previousPreferences
        }
        try await body(preferences)
    }

    /// The promise the whole design rests on: while the mode is off, an event
    /// is not merely discarded — it is never built. These call sites sit
    /// inside a 50 ms budget.
    @Test func anEventIsNotEvenConstructedWhileTheModeIsOff() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        await withFacade(expiry: nil, directory: directory) { _ in
            var built = false
            DebugLog.record({ built = true; return .launcher(.opened) }())
            #expect(built == false)
        }
    }

    @Test func nothingIsWrittenWhileTheModeIsOff() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await withFacade(expiry: nil, directory: directory) { _ in
            DebugLog.record(.launcher(.opened))
            try await Task.sleep(for: .milliseconds(100))
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(contents.isEmpty)
        }
    }

    @Test func aliveSessionWrites() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await withFacade(
            expiry: Date().addingTimeInterval(60), directory: directory
        ) { _ in
            DebugLog.record(.launcher(.opened))
            try await Task.sleep(for: .milliseconds(100))
            let exported = String(decoding: try await DebugLog.store.export(), as: UTF8.self)
            #expect(exported.contains("opened"))
        }
    }

    /// A deadline that passed while Pium was closed is settled by the first
    /// event after the next launch — and settled means the preference stops
    /// claiming a session is running.
    @Test func apassedDeadlineStopsRecordingAndClearsItself() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await withFacade(
            expiry: Date().addingTimeInterval(-1), directory: directory
        ) { preferences in
            DebugLog.record(.launcher(.opened))
            #expect(preferences.debugLoggingExpiry == nil)
            try await Task.sleep(for: .milliseconds(100))
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(contents.isEmpty)
        }
    }
}
