import Foundation

/// Something the user named once and opens from the launcher afterwards.
///
/// A bookmark runs no process. It names a destination and, at most, the
/// application to open it with — which is what keeps it out of `PluginCore`
/// and out of the single run slot `ExecutionManager` hands out.
struct Bookmark: Identifiable, Sendable, Equatable, Codable {
    /// Stable for the life of the bookmark, and deliberately not the name:
    /// the frecency history and the list's selection are keyed by it, so
    /// renaming a bookmark would otherwise throw away everything Pium had
    /// learned about it.
    let id: UUID
    var name: String
    var destination: BookmarkDestination
    /// Other words this answers to, scored alongside the name.
    var keywords: [String]
    /// The bundle identifier of the application this opens with. `nil` leaves
    /// the choice to whatever macOS would use for the destination.
    var openWith: String?

    init(
        id: UUID = UUID(),
        name: String,
        destination: BookmarkDestination,
        keywords: [String] = [],
        openWith: String? = nil
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.keywords = keywords
        self.openWith = openWith
    }
}
