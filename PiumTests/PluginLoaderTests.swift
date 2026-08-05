import Testing
import Foundation
@testable import Pium

@Suite("Plugin loading")
struct PluginLoaderTests {
    /// A real directory per test. Deliberately not under ~/Documents: the unit
    /// test host inherits whatever TCC grants launched xcodebuild, so a
    /// protected folder makes the suite pass or fail by machine.
    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ json: String, named name: String, in root: URL) throws {
        try json.write(
            to: root.appending(path: name), atomically: true, encoding: .utf8
        )
    }

    private let valid = """
    { "schemaVersion": 1, "id": "web.youtube", "name": "YouTube",
      "command": { "executable": "open", "arguments": ["https://youtube.com"] } }
    """

    @Test func anEmptyDirectoryLoadsNothing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PluginLoader.load(from: root).isEmpty)
    }

    @Test func amissingDirectoryLoadsNothingRatherThanFailing() {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(PluginLoader.load(from: root).isEmpty)
    }

    @Test func avalidManifestBecomesAValidRecord() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(valid, named: "youtube.pium.json", in: root)

        let records = PluginLoader.load(from: root)
        #expect(records.count == 1)
        #expect(records.first?.isValid == true)
        #expect(records.first?.manifest?.id == "web.youtube")
        #expect(records.first?.id == "web.youtube")
    }

    /// PRD §10.1: one invalid plugin cannot block the others.
    @Test func aninvalidManifestDoesNotStopTheOthersLoading() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(valid, named: "youtube.pium.json", in: root)
        try write("{ not json", named: "broken.pium.json", in: root)

        let records = PluginLoader.load(from: root)
        #expect(records.count == 2)
        #expect(records.filter(\.isValid).count == 1)
        #expect(records.first { !$0.isValid }?.diagnostic != nil)
    }

    /// An undecodable file has no manifest id, so the path stands in — the
    /// record still has to be identifiable to appear in a list.
    @Test func aninvalidRecordIsIdentifiedByItsPath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{ not json", named: "broken.pium.json", in: root)

        let record = try #require(PluginLoader.load(from: root).first)
        #expect(record.id == record.fileURL.path)
    }

    @Test func onlyPiumManifestsAreRead() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(valid, named: "youtube.pium.json", in: root)
        try write("notes", named: "README.md", in: root)
        try write(valid, named: "other.json", in: root)

        #expect(PluginLoader.load(from: root).count == 1)
    }

    /// Deterministic order, so the conflict rule in `PluginIndex` picks the same
    /// winner on every launch rather than whatever the filesystem returned.
    @Test func recordsComeBackInAStableOrder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["c", "a", "b"] {
            try write(
                valid.replacingOccurrences(of: "web.youtube", with: "web.\(name)"),
                named: "\(name).pium.json",
                in: root
            )
        }
        #expect(PluginLoader.load(from: root).map(\.manifest?.id) == ["web.a", "web.b", "web.c"])
    }

    @Test func creatingTheRootIsIdempotent() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        PluginLoader.createRootIfNeeded(root)
        PluginLoader.createRootIfNeeded(root)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func theDefaultRootIsUnderDotConfig() {
        #expect(PluginLoader.defaultRoot.path.hasSuffix(".config/pium/plugins"))
    }
}
