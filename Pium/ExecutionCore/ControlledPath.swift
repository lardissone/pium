import Foundation

/// Where a bare executable name is looked for.
///
/// Deliberately not the launching process's `PATH`: Pium opened from the Finder
/// and Pium opened from a terminal carry different environments, and a plugin
/// that works one way and not the other is a bug nobody can reproduce. Phase 6's
/// Advanced section lets a user append to this.
enum ControlledPath {
    static let `default`: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
}
