import Testing
import Foundation
@testable import Pium

@Suite("Application scanning")
struct ApplicationScannerTests {
    /// Builds a throwaway directory holding fake `.app` bundles, so the tests
    /// describe exactly which shapes are accepted rather than depending on
    /// whatever happens to be installed.
    private func makeFixture(
        _ bundles: [(name: String, plist: [String: Any])]
    ) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        for bundle in bundles {
            let contents = root
                .appending(path: "\(bundle.name).app")
                .appending(path: "Contents")
            try FileManager.default.createDirectory(
                at: contents, withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: bundle.plist, format: .xml, options: 0
            )
            try data.write(to: contents.appending(path: "Info.plist"))
        }
        return root
    }

    private func launchable(_ name: String) -> (name: String, plist: [String: Any]) {
        (name, ["CFBundleIdentifier": "test.\(name)", "CFBundlePackageType": "APPL"])
    }

    @Test func scanFindsLaunchableBundles() throws {
        let root = try makeFixture([launchable("Safari"), launchable("Mail")])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ApplicationScanner.scan(roots: [root], fileManager: .default)
        #expect(Set(found.map(\.name)) == ["Safari", "Mail"])
    }

    /// Background-only bundles are helpers, not things a user launches.
    @Test func backgroundOnlyBundlesAreExcluded() throws {
        let root = try makeFixture([
            launchable("Visible"),
            ("Helper", [
                "CFBundleIdentifier": "test.helper",
                "CFBundlePackageType": "APPL",
                "LSBackgroundOnly": true,
            ]),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ApplicationScanner.scan(roots: [root], fileManager: .default)
        #expect(found.map(\.name) == ["Visible"])
    }

    /// A bundle with no `Info.plist` is not an application.
    @Test func bundlesWithoutAnInfoPlistAreExcluded() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Broken.app"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ApplicationScanner.scan(roots: [root], fileManager: .default).isEmpty)
    }

    /// A missing directory is normal — not every machine has `~/Applications`.
    @Test func aMissingRootIsIgnored() {
        let absent = URL.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(ApplicationScanner.scan(roots: [absent], fileManager: .default).isEmpty)
    }

    /// Identity is the bundle path: two apps can share a name, and the same app
    /// must keep its ID across rescans so selection stays stable.
    @Test func identityIsTheBundlePath() throws {
        let root = try makeFixture([launchable("Safari")])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ApplicationScanner.scan(roots: [root], fileManager: .default)
        #expect(found.first?.id == found.first?.bundleURL.path)
    }

    /// `/Applications/Safari.app` is a symlink into the cryptex and carries the
    /// hidden flag, so a scan that skips hidden entries finds no Safari at all.
    @Test func bundlesCarryingTheHiddenFlagAreStillFound() throws {
        let root = try makeFixture([launchable("Safari")])
        defer { try? FileManager.default.removeItem(at: root) }

        var bundle = root.appending(path: "Safari.app")
        var values = URLResourceValues()
        values.isHidden = true
        try bundle.setResourceValues(values)

        let found = ApplicationScanner.scan(roots: [root], fileManager: .default)
        #expect(found.map(\.name) == ["Safari"])
    }

    /// Dot-prefixed entries such as `.localized` are noise, not applications.
    @Test func dotPrefixedEntriesAreSkipped() throws {
        let root = try makeFixture([launchable("Visible")])
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: ".localized"))

        let found = ApplicationScanner.scan(roots: [root], fileManager: .default)
        #expect(found.map(\.name) == ["Visible"])
    }

    /// The shipped roots must cover the three locations the PRD names.
    @Test func searchRootsCoverSystemGlobalAndUserLocations() {
        let paths = ApplicationScanner.searchRoots.map(\.path)
        #expect(paths.contains("/Applications"))
        #expect(paths.contains("/System/Applications"))
        #expect(paths.contains { $0.hasSuffix("/Applications") && $0.hasPrefix(NSHomeDirectory()) })
    }
}
