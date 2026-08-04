import Foundation

/// An application bundle Pium can launch.
struct InstalledApplication: Sendable, Equatable, Identifiable {
    /// The bundle path. Stable across rescans, and unique even when two
    /// applications share a display name.
    var id: String { bundleURL.path }

    let name: String
    let bundleURL: URL
    let bundleIdentifier: String?
}

/// Finds installed applications by walking the known application directories.
///
/// A directory scan rather than a Spotlight query: it needs no index, behaves
/// the same on a machine with indexing disabled, and is testable against a
/// fixture directory. Spotlight arrives in Phase 3 for files, where there is no
/// alternative.
enum ApplicationScanner {
    /// Where macOS keeps launchable applications.
    static let searchRoots: [URL] = [
        URL(filePath: "/Applications"),
        URL(filePath: "/System/Applications"),
        URL(filePath: "/System/Applications/Utilities"),
        URL(filePath: "/Applications/Utilities"),
        URL.homeDirectory.appending(path: "Applications"),
    ]

    /// How deep to descend. Application folders nest one level — `/Applications/
    /// Utilities/Terminal.app` — but nothing sane goes deeper, and unbounded
    /// recursion would walk entire bundle contents.
    private static let maximumDepth = 2

    static func scan(
        roots: [URL] = searchRoots,
        fileManager: FileManager = .default
    ) -> [InstalledApplication] {
        var found: [String: InstalledApplication] = [:]
        for root in roots {
            for application in scan(root: root, depth: 0, fileManager: fileManager) {
                // Roots overlap; first find wins and the result stays unique.
                found[application.id] = found[application.id] ?? application
            }
        }
        return Array(found.values).sorted { $0.name < $1.name }
    }

    private static func scan(
        root: URL,
        depth: Int,
        fileManager: FileManager
    ) -> [InstalledApplication] {
        guard depth < maximumDepth else { return [] }
        // A missing root is normal: not every machine has `~/Applications`.
        //
        // `.skipsHiddenFiles` is deliberately absent: `/Applications/Safari.app`
        // is a symlink into the cryptex carrying the hidden flag, and skipping
        // hidden entries would drop Safari from every result. Dot-prefixed names
        // are filtered by hand instead.
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var found: [InstalledApplication] = []
        for entry in entries {
            if entry.lastPathComponent.hasPrefix(".") {
                continue
            } else if entry.pathExtension == "app" {
                if let application = application(at: entry) { found.append(application) }
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory == true {
                found += scan(root: entry, depth: depth + 1, fileManager: fileManager)
            }
        }
        return found
    }

    private static func application(at bundleURL: URL) -> InstalledApplication? {
        let plistURL = bundleURL.appending(path: "Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any]
        else {
            return nil
        }

        guard isLaunchable(bundleURL: bundleURL, infoPlist: plist) else { return nil }

        return InstalledApplication(
            name: bundleURL.deletingPathExtension().lastPathComponent,
            bundleURL: bundleURL,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String
        )
    }

    /// Whether a bundle is something a user launches, as opposed to a helper,
    /// an agent, or an uninstaller that happens to live in an app directory.
    static func isLaunchable(bundleURL: URL, infoPlist: [String: Any]?) -> Bool {
        guard let infoPlist else { return false }
        if infoPlist["LSBackgroundOnly"] as? Bool == true { return false }
        if infoPlist["LSUIElement"] as? Bool == true { return false }
        return true
    }
}
