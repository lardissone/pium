import Foundation

/// Where a bare executable name is looked for.
///
/// Deliberately not the launching process's `PATH`: Pium opened from the Finder
/// and Pium opened from a terminal carry different environments, and a plugin
/// that works one way and not the other is a bug nobody can reproduce. The
/// Advanced section of Settings appends to this.
enum ControlledPath {
    static let `default`: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// The defaults followed by whatever the user added, each directory once.
    ///
    /// Additions always come last. A directory added in Advanced is there to
    /// *find* something the defaults miss — `~/.local/bin`, a version-manager
    /// shim — not to redefine a tool that already resolves, and appending is
    /// what makes shadowing impossible rather than merely discouraged.
    static func effective(adding additions: [String]) -> [String] {
        var seen = Set(`default`)
        return `default` + additions.filter { seen.insert($0).inserted }
    }
}
