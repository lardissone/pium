import Foundation

/// An available version, in the form the notice announces it.
///
/// Deliberately not `SUAppcastItem`: the launcher and Settings render this,
/// and neither should have to import Sparkle to be testable.
struct PendingUpdate: Equatable, Sendable {
    /// What the user reads: "0.2.0".
    let version: String
}
