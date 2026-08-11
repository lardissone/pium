import Testing
import Foundation
@testable import Pium

@Suite("Protected folder access")
@MainActor
struct ProtectedFolderAccessTests {
    /// Records what was read, so a test can assert that nothing was.
    ///
    /// Locked because the reader is called on the main actor by `status(of:)`
    /// and on a thread of its own by `request` and `statuses(of:then:)`, and
    /// the same recorder is used for all of them.
    private final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URL] = []

        func record(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(url)
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }
    }

    private func access(
        alreadyRequested: Set<String> = [],
        answer: @escaping @Sendable (URL) throws -> Void = { _ in }
    ) -> ProtectedFolderAccess {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.requestedFolderAccess = alreadyRequested
        return ProtectedFolderAccess(preferences: preferences, read: answer)
    }

    /// The guarantee that launching Pium raises no prompt: a folder nobody has
    /// asked about is reported from what Pium remembers, and is never read —
    /// reading a folder whose status is undetermined is what makes macOS ask.
    @Test func afolderNeverAskedAboutIsNotRequestedAndIsNeverRead() {
        let reads = Reads()
        let subject = access { reads.record($0) }

        #expect(subject.status(of: .documents) == .notRequested)
        #expect(reads.urls.isEmpty, "Asking about an unrequested folder must not touch it")
    }

    @Test func afolderThatReadsIsGranted() {
        let subject = access(alreadyRequested: ["documents"])
        #expect(subject.status(of: .documents) == .granted)
    }

    /// A refusal is what `blocked` means.
    @Test func afolderThatRefusesIsBlocked() {
        let subject = access(alreadyRequested: ["desktop"]) { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        }
        #expect(subject.status(of: .desktop) == .blocked)
    }

    /// A folder that is simply not there is not blocking anybody. Reporting it
    /// as blocked would send the user to System Settings to grant access to
    /// something that does not exist.
    @Test func amissingFolderIsNotReportedAsBlocked() {
        let subject = access(alreadyRequested: ["downloads"]) { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        }
        #expect(subject.status(of: .downloads) == .granted)
    }

    /// Asking is what turns `notRequested` into an answer, and the asking is
    /// recorded so the next launch does not raise the prompt again.
    @Test func requestingRecordsTheFolderAndReportsItsStatus() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let subject = ProtectedFolderAccess(preferences: preferences) { _ in }
        #expect(subject.status(of: .documents) == .notRequested)

        let reported: [ProtectedFolder: ProtectedFolderAccess.Status] = await withCheckedContinuation {
            continuation in
            subject.request([.documents]) { statuses in
                continuation.resume(returning: statuses)
            }
        }

        #expect(reported[.documents] == .granted)
        #expect(preferences.requestedFolderAccess.contains("documents"))
        #expect(subject.status(of: .documents) == .granted)
    }

    /// Every folder asked for comes back in the report, including one that
    /// refused: the caller redraws from this and cannot leave a row blank.
    @Test func requestingReportsEveryFolderItWasGiven() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let subject = ProtectedFolderAccess(preferences: preferences) { url in
            guard url.lastPathComponent != "Desktop" else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            }
        }

        let reported: [ProtectedFolder: ProtectedFolderAccess.Status] = await withCheckedContinuation {
            continuation in
            subject.request(ProtectedFolder.allCases) { continuation.resume(returning: $0) }
        }

        #expect(reported.count == 3)
        #expect(reported[.desktop] == .blocked)
        #expect(reported[.documents] == .granted)
    }

    /// The same folder twice is a caller's slip. Killing the app for it, in the
    /// middle of a permission flow, is not a proportionate answer.
    @Test func requestingTheSameFolderTwiceReportsItOnce() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let subject = ProtectedFolderAccess(preferences: preferences) { _ in }

        let reported: [ProtectedFolder: ProtectedFolderAccess.Status] = await withCheckedContinuation {
            continuation in
            subject.request([.documents, .documents]) { continuation.resume(returning: $0) }
        }

        #expect(reported == [.documents: .granted])
    }

    /// The refresh path answers for everything it was handed, so no row is left
    /// without a status to draw.
    @Test func refreshingReportsEveryFolderItWasGiven() async {
        let subject = access(alreadyRequested: ["documents", "desktop", "downloads"]) { url in
            guard url.lastPathComponent != "Desktop" else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            }
        }

        let reported = await statuses(from: subject, of: ProtectedFolder.allCases)

        #expect(reported.count == 3)
        #expect(reported[.desktop] == .blocked)
        #expect(reported[.documents] == .granted)
        #expect(reported[.downloads] == .granted)
    }

    /// The refresh runs on every activation of Pium, so it has to honour the
    /// same guarantee as `status(of:)`: a folder nobody asked about is answered
    /// from memory, never by touching it.
    @Test func refreshingNeverReadsAfolderNobodyAskedAbout() async {
        let reads = Reads()
        let subject = access(alreadyRequested: ["desktop"]) { reads.record($0) }

        let reported = await statuses(from: subject, of: ProtectedFolder.allCases)

        #expect(reported[.documents] == .notRequested)
        #expect(reported[.downloads] == .notRequested)
        #expect(reported[.desktop] == .granted)
        #expect(reads.urls == [ProtectedFolder.desktop.url])
    }

    @Test func refreshingTheSameFolderTwiceReportsItOnce() async {
        let subject = access(alreadyRequested: ["documents"])

        let reported = await statuses(from: subject, of: [.documents, .documents])

        #expect(reported == [.documents: .granted])
    }

    private func statuses(
        from subject: ProtectedFolderAccess,
        of folders: [ProtectedFolder]
    ) async -> [ProtectedFolder: ProtectedFolderAccess.Status] {
        await withCheckedContinuation { continuation in
            subject.statuses(of: folders) { continuation.resume(returning: $0) }
        }
    }
}
