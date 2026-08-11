import Foundation

/// A folder macOS keeps behind a privacy prompt.
///
/// Spotlight does not report these as refused — it filters them out of the
/// results silently — so a user with no access sees an empty search rather
/// than an error (PIUM-41).
///
/// The raw values are persisted in `Preferences`, so renaming a case is a
/// migration.
enum ProtectedFolder: String, CaseIterable, Sendable {
    case documents
    case desktop
    case downloads

    var url: URL {
        switch self {
        case .documents: URL.homeDirectory.appending(path: "Documents", directoryHint: .isDirectory)
        case .desktop: URL.homeDirectory.appending(path: "Desktop", directoryHint: .isDirectory)
        case .downloads: URL.homeDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
        }
    }

    var title: String {
        switch self {
        case .documents: String(localized: "folder.documents")
        case .desktop: String(localized: "folder.desktop")
        case .downloads: String(localized: "folder.downloads")
        }
    }
}
