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
