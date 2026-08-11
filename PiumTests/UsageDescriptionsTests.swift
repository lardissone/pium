import Testing
import Foundation
@testable import Pium

/// The sentence macOS shows in its own prompt comes from the bundle, not from
/// Pium's strings catalog. Without these keys the prompt carries no
/// explanation at all, which is a worse thing to show somebody than no prompt.
@Suite("Usage descriptions")
struct UsageDescriptionsTests {
    @Test(arguments: [
        "NSDocumentsFolderUsageDescription",
        "NSDesktopFolderUsageDescription",
        "NSDownloadsFolderUsageDescription",
    ])
    func theBundleExplainsWhyEachFolderIsWanted(key: String) throws {
        let value = try #require(
            Bundle.main.object(forInfoDictionaryKey: key) as? String,
            "\(key) is missing from the built Info.plist"
        )
        #expect(!value.isEmpty)
    }
}
