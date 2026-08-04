import Foundation

/// Where file search looks.
///
/// The raw values are persisted, so renaming a case is a migration.
enum FileSearchScope: String, CaseIterable, Sendable {
    /// Everything under the user's home directory. The default.
    case home
    /// Every indexed local volume. Opt-in, because it surfaces system files
    /// most people are not looking for.
    case allIndexedLocal

    /// The constant `NSMetadataQuery.searchScopes` expects.
    var metadataScope: String {
        switch self {
        case .home: NSMetadataQueryUserHomeScope
        case .allIndexedLocal: NSMetadataQueryLocalComputerScope
        }
    }
}
