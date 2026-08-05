import Foundation

/// What one file turned out to be: a plugin, or the reason it is not one.
///
/// Both outcomes are records because an invalid manifest still has to appear —
/// in the result list now, and in Preferences in 4b. A file that vanishes from
/// the model is a file whose author never learns what is wrong with it.
struct PluginRecord: Sendable, Identifiable {
    let fileURL: URL
    let manifest: PluginManifest?
    let diagnostic: PluginDiagnostic?

    /// The manifest's id when there is one. An undecodable file has none, so its
    /// path stands in — unique, stable, and meaningful to whoever has to open it.
    var id: String { manifest?.id ?? fileURL.path }

    var isValid: Bool { manifest != nil }

    /// The same record, invalidated by a conflict with another file.
    func invalidated(by diagnostic: PluginDiagnostic) -> PluginRecord {
        PluginRecord(fileURL: fileURL, manifest: nil, diagnostic: diagnostic)
    }
}
