import Foundation

/// An available version, in the two forms a person and a comparison need.
///
/// Deliberately not `SUAppcastItem`: the launcher and Settings render this,
/// and neither should have to import Sparkle to be testable.
struct PendingUpdate: Equatable, Sendable {
    /// What the user reads: "0.2.0".
    let version: String
    /// What sorts: the build number.
    let build: String
}
