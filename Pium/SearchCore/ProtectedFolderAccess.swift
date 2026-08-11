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
    func status(of folder: ProtectedFolder) -> Status {
        guard preferences.requestedFolderAccess.contains(folder.rawValue) else {
            return .notRequested
        }
        do {
            try read(folder.url)
            return .granted
        } catch {
            return Self.isRefusal(error) ? .blocked : .granted
        }
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
            for folder in folders {
                // The answer is not read here: what matters is that the ask
                // happened. `status(of:)` reports it afterwards, from the main
                // actor, where `preferences` can be touched.
                try? read(folder.url)
            }
            Task { @MainActor in
                preferences.requestedFolderAccess.formUnion(folders.map(\.rawValue))
                report(Dictionary(uniqueKeysWithValues: folders.map { ($0, status(of: $0)) }))
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

    /// A refusal, as opposed to any other reason a read can fail. A folder that
    /// is not there is not blocking anybody, so it counts as granted: reporting
    /// it as blocked would send the user to System Settings to grant access to
    /// something that does not exist.
    ///
    /// `NSFileReadNoPermissionError` is what Foundation reports for both
    /// `EPERM` and `EACCES`.
    private static func isRefusal(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
    }

    /// The real read, listing the directory rather than stat-ing it: the
    /// listing is what TCC guards.
    ///
    /// `nonisolated` because `DirectoryReader` carries no actor isolation —
    /// `request` (Task 2) runs it off the main actor, on a thread of its own.
    nonisolated static func readDirectory(_ url: URL) throws {
        _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
}
