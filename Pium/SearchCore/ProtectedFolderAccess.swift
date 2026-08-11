import AppKit
import Foundation

/// Whether Pium may read the folders macOS protects.
///
/// The only place in Pium that knows TCC exists.
@MainActor
final class ProtectedFolderAccess {
    enum Status: Equatable, Sendable {
        /// Nobody has asked yet. Not something macOS will tell us — see
        /// `status(of:)`.
        case notRequested
        case granted
        case blocked
    }

    /// Reads a directory, which is the act that makes macOS ask. Injected so a
    /// test can answer without raising a real prompt.
    typealias DirectoryReader = @Sendable (URL) throws -> Void

    private let preferences: Preferences
    private let read: DirectoryReader

    init(
        preferences: Preferences,
        read: @escaping DirectoryReader = ProtectedFolderAccess.readDirectory
    ) {
        self.preferences = preferences
        self.read = read
    }

    /// macOS exposes no way to read TCC's answer without triggering it:
    /// reading a folder whose status is undetermined *asks*. So a folder Pium
    /// has never asked about is answered from what Pium remembers asking, and
    /// deliberately not read here — reading it would raise a prompt nobody
    /// provoked, which is exactly what PRD §9 rules out.
    ///
    /// Synchronous, so it reads on whatever thread calls it. No interface path
    /// uses it for that reason: they go through `statuses(of:then:)`.
    func status(of folder: ProtectedFolder) -> Status {
        Self.status(
            of: folder,
            requested: preferences.requestedFolderAccess,
            read: read
        )
    }

    /// Reports where each of `folders` stands, reading them off the main actor.
    ///
    /// What Pium remembers asking and what TCC records can drift apart — the
    /// person removes Pium from Privacy & Security, `tccutil reset` runs, the
    /// signature changes — and TCC is then undetermined again while Pium still
    /// believes it asked. The read raises a prompt, and a prompt blocks the
    /// thread that provoked it until the person answers, so this cannot happen
    /// on the main actor (PIUM-41).
    ///
    /// A thread rather than a share of `DispatchQueue.global`, for the reason
    /// `request` documents.
    func statuses(
        of folders: [ProtectedFolder],
        then report: @escaping @MainActor ([ProtectedFolder: Status]) -> Void
    ) {
        let read = self.read
        // Read here, on the main actor, because `preferences` lives on it. The
        // thread gets the answer rather than the store.
        let requested = preferences.requestedFolderAccess
        let thread = Thread {
            let reported = folders.map {
                ($0, Self.status(of: $0, requested: requested, read: read))
            }
            Task { @MainActor in
                report(Dictionary(reported, uniquingKeysWith: { _, new in new }))
            }
        }
        thread.name = "com.pium.folder-access"
        thread.start()
    }

    /// Asks macOS about each folder in turn, then reports where every one of
    /// them ended up.
    ///
    /// On a thread of its own because the prompt blocks whatever thread made
    /// the call until the person answers it: asking from the main actor
    /// freezes the interface for as long as they take to decide. One folder at
    /// a time, so three dialogs do not land on top of each other.
    ///
    /// A thread rather than a share of `DispatchQueue.global`, for the reason
    /// `ProcessRunner` uses one: a wait that lasts as long as a person takes
    /// does not belong in a pool of bounded width (PIUM-109).
    func request(
        _ folders: [ProtectedFolder],
        then report: @escaping @MainActor ([ProtectedFolder: Status]) -> Void
    ) {
        let read = self.read
        let thread = Thread { [self] in
            // The ask *is* the read, so its outcome is the answer. Classifying
            // it here rather than afterwards spares the folders a second
            // listing, which the prompt has just made expensive.
            let reported = folders.map { ($0, Self.status(ofReading: $0.url, with: read)) }
            Task { @MainActor in
                preferences.requestedFolderAccess.formUnion(folders.map(\.rawValue))
                // Pium has no Dock icon, so it does not get the front back on
                // its own when the system's prompt closes: macOS hands it to
                // whatever ordinary application is next in line, and the
                // window somebody was reading disappears behind Finder.
                NSApp.activate()
                // Uniquing rather than `uniqueKeysWithValues:`, which traps:
                // the same folder twice in one call is a caller's slip, not
                // grounds for killing the app inside a permission flow.
                report(Dictionary(reported, uniquingKeysWith: { _, new in new }))
            }
        }
        thread.name = "com.pium.folder-access"
        thread.start()
    }

    /// Opens Privacy & Security ▸ Files and Folders, which is the only route
    /// back once a folder has been refused: macOS does not ask a second time.
    func openSystemSettings() {
        guard let url = URL(string: Self.filesAndFoldersSettings) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let filesAndFoldersSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

    /// The classification itself, `nonisolated` so both the main actor and the
    /// threads above can reach it. `requested` is what Pium remembers asking,
    /// handed over as a value because `preferences` belongs to the main actor.
    private nonisolated static func status(
        of folder: ProtectedFolder,
        requested: Set<String>,
        read: DirectoryReader
    ) -> Status {
        guard requested.contains(folder.rawValue) else { return .notRequested }
        return status(ofReading: folder.url, with: read)
    }

    /// What the read says about a folder Pium has already asked about.
    private nonisolated static func status(
        ofReading url: URL,
        with read: DirectoryReader
    ) -> Status {
        do {
            try read(url)
            return .granted
        } catch {
            return isRefusal(error) ? .blocked : .granted
        }
    }

    /// A refusal, as opposed to any other reason a read can fail. A folder that
    /// is not there is not blocking anybody, so it counts as granted: reporting
    /// it as blocked would send the user to System Settings to grant access to
    /// something that does not exist.
    ///
    /// `NSFileReadNoPermissionError` is what Foundation reports for both
    /// `EPERM` and `EACCES`.
    private nonisolated static func isRefusal(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
    }

    /// The real read, listing the directory rather than stat-ing it: the
    /// listing is what TCC guards.
    ///
    /// `nonisolated` because `DirectoryReader` carries no actor isolation —
    /// `request` runs it off the main actor, on a thread of its own.
    nonisolated static func readDirectory(_ url: URL) throws {
        _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
}
