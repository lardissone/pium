import Testing
import Foundation
@testable import Pium

@Suite("Debug log store")
struct DebugLogStoreTests {
    /// A clock the test moves and the store reads.
    ///
    /// The store takes a `@Sendable` closure, and a plain `var` captured by
    /// one is a data race Swift 6 refuses to compile. The lock is what makes
    /// the two sides of that closure legal rather than merely unlikely to
    /// collide.
    private final class MutableClock: @unchecked Sendable {
        private let lock = NSLock()
        private var moment: Date

        init(_ moment: Date) {
            self.moment = moment
        }

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return moment
        }

        func advance(by interval: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            moment += interval
        }
    }

    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func segments(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func event(_ text: String) -> DebugEvent {
        .search(query: text, results: 1, duration: .milliseconds(1))
    }

    @Test func writingAnEventLeavesALineOnDisk() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DebugLogStore(directory: directory, now: { Date() })

        await store.write(event("fire"))

        let exported = String(decoding: try await store.export(), as: UTF8.self)
        #expect(exported.contains("\"fire\""))
        #expect(exported.hasSuffix("\n"), "every record ends its own line")
    }

    /// The directory can hold a user's search text. Another account on the
    /// same Mac has no business reading it.
    @Test func thedirectoryIsReadableOnlyByItsOwner() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DebugLogStore(directory: root, now: { Date() })

        await store.write(event("fire"))

        let permissions = try FileManager.default
            .attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        let expected: Int16 = 0o700
        #expect(permissions?.int16Value == expected)
    }

    /// A single file could only be truncated, which loses either the
    /// beginning of the story or the end of it. Segments are what make
    /// eviction possible at all.
    @Test func passingTheSegmentCapStartsAnotherSegment() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let store = DebugLogStore(directory: directory, now: { clock.now })

        // Each line is far past the cap on its own, so the second write cannot
        // land in the first segment.
        let long = String(repeating: "x", count: DebugLogStore.segmentSizeLimit + 1)
        await store.write(event(long))
        clock.advance(by: 1)
        await store.write(event(long))

        #expect(try segments(in: directory).count == 2)
    }

    @Test func theoldestSegmentsGoWhenTheTotalPassesItsLimit() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let store = DebugLogStore(directory: directory, now: { clock.now })

        // Lines that fit inside a segment, as every real one does: the output
        // cap bounds a `finished` line to a couple of hundred kilobytes, and a
        // query to whatever a person can type. Twenty-four megabytes of them
        // is comfortably past the ceiling.
        let long = String(repeating: "x", count: 512 * 1024)
        for _ in 0..<48 {
            await store.write(event(long))
            clock.advance(by: 1)
        }

        let total = try segments(in: directory).reduce(0) { sum, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
            return sum + (size ?? 0)
        }
        #expect(total <= DebugLogStore.totalSizeLimit, "24 MB was written; 20 MB is the ceiling")
        #expect(try !segments(in: directory).isEmpty, "eviction must not take everything")
    }

    /// Twenty megabytes or seven days, whichever comes first (PRD §14). A
    /// quiet week is the case the size limit never catches.
    @Test func asegmentOlderThanAweekIsDeleted() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appending(path: "pium-19700101-000000-000.log")
        try "ancient\n".write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path
        )
        let store = DebugLogStore(
            directory: directory, now: { Date(timeIntervalSince1970: 1_000_000) }
        )

        await store.write(event("fire"))

        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func exportReadsTheSegmentsOldestFirst() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let store = DebugLogStore(directory: directory, now: { clock.now })

        let long = String(repeating: "x", count: DebugLogStore.segmentSizeLimit + 1)
        await store.write(event("first"))
        await store.write(event(long))
        clock.advance(by: 1)
        await store.write(event("second"))

        let exported = String(decoding: try await store.export(), as: UTF8.self)
        let first = try #require(exported.range(of: "\"first\""))
        let second = try #require(exported.range(of: "\"second\""))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test func deletingLeavesNothingBehind() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DebugLogStore(directory: directory, now: { Date() })
        await store.write(event("fire"))

        await store.deleteAll()

        #expect(try segments(in: directory).isEmpty)
        #expect(try await store.export().isEmpty)
    }

    /// Deleting mid-session must not leave the store writing into a file that
    /// is no longer there.
    @Test func writingAfterDeletingStartsAfreshSegment() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DebugLogStore(directory: directory, now: { Date() })
        await store.write(event("before"))
        await store.deleteAll()

        await store.write(event("after"))

        let exported = String(decoding: try await store.export(), as: UTF8.self)
        #expect(exported.contains("\"after\""))
        #expect(!exported.contains("\"before\""))
    }
}
