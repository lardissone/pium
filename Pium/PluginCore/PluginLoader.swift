import Foundation
import OSLog

/// Reads the plugin directory into records.
///
/// Every file is decoded and validated on its own, and a failure becomes a
/// record rather than an error that escapes — one broken manifest must never
/// stop the others loading (PRD §10.1).
enum PluginLoader {
    private static let logger = Logger(subsystem: Signposts.subsystem, category: "Plugins")

    /// The extension the documentation recommends. Anything else in the folder
    /// — a README, a script, a `.git` directory — is left alone.
    static let manifestSuffix = ".pium.json"

    /// `~/.config/pium/plugins`.
    static var defaultRoot: URL {
        URL(filePath: NSHomeDirectory())
            .appending(path: ".config")
            .appending(path: "pium")
            .appending(path: "plugins")
    }

    static func createRootIfNeeded(_ root: URL = defaultRoot) {
        do {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true
            )
        } catch {
            logger.error("Could not create the plugins folder: \(error)")
        }
    }

    static func load(from root: URL = defaultRoot) -> [PluginRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []

        return names
            .filter { $0.hasSuffix(manifestSuffix) }
            // Sorted so duplicate resolution picks the same winner every launch
            // rather than following directory order.
            .sorted()
            .map { record(at: root.appending(path: $0)) }
    }

    private static func record(at url: URL) -> PluginRecord {
        guard let data = try? Data(contentsOf: url) else {
            return PluginRecord(fileURL: url, manifest: nil, diagnostic: .unreadableFile)
        }

        switch ManifestDecoder.decode(data) {
        case .failure(let diagnostic):
            return PluginRecord(fileURL: url, manifest: nil, diagnostic: diagnostic)
        case .success(let manifest):
            if let diagnostic = ManifestValidator.validate(manifest) {
                return PluginRecord(fileURL: url, manifest: nil, diagnostic: diagnostic)
            }
            return PluginRecord(fileURL: url, manifest: manifest, diagnostic: nil)
        }
    }
}
