import Testing
import Foundation
@testable import Pium

@Suite("Spotlight query")
struct SpotlightQueryTests {
    /// The PRD starts file search at two characters: one character matches most
    /// of the disk and is never what the user meant.
    @Test func theMinimumQueryLengthIsTwo() {
        #expect(SpotlightQuery.minimumQueryLength == 2)
    }

    /// The predicate has to survive a query containing quotes and wildcards
    /// without becoming a different query. Building it with a format string and
    /// arguments, rather than by interpolation, is what guarantees that.
    @Test(arguments: ["report", "budget 2026", "a\"b", "*", "it's"])
    func theQueryIsCarriedAsAnArgumentNotInterpolated(text: String) {
        let predicate = SpotlightQuery.predicate(for: TextNormalizer.query(text))
        #expect(predicate.predicateFormat.contains("kMDItemDisplayName"))
        #expect(!predicate.predicateFormat.hasPrefix(text))
    }

    @Test func applicationsAreExcludedSoTheyDoNotDuplicateTheAppProvider() {
        let predicate = SpotlightQuery.predicate(for: TextNormalizer.query("safari"))
        #expect(predicate.predicateFormat.contains("com.apple.application-bundle"))
    }

    @Test(arguments: [
        "/Users/someone/Documents/report.pdf",
        "/Users/someone/Desktop/notes.md",
        "/Users/someone/Developer/Projects/pium/README.md",
    ])
    func ordinaryUserFilesArePresentable(path: String) {
        #expect(SpotlightQuery.isPresentable(URL(filePath: path)))
    }

    /// Library, caches, and hidden paths are technical noise. They are the
    /// difference between a useful file search and an unusable one.
    @Test(arguments: [
        "/Users/someone/Library/Caches/whatever/file.txt",
        "/Users/someone/Library/Containers/com.example/Data/x.plist",
        "/Users/someone/.config/pium/plugins/thing.json",
        "/Users/someone/Documents/.hidden/secret.txt",
        "/Users/someone/Projects/app/node_modules/pkg/index.js",
        "/Users/someone/Projects/app/.git/config",
    ])
    func technicalNoiseIsExcluded(path: String) {
        #expect(!SpotlightQuery.isPresentable(URL(filePath: path)))
    }

    /// A bundle that slipped through the predicate is still not a file result.
    @Test func applicationBundlesAreExcludedByPathToo() {
        #expect(!SpotlightQuery.isPresentable(URL(filePath: "/Applications/Safari.app")))
    }

    /// The subtitle disambiguates same-named files, so it has to show where the
    /// file is, abbreviated the way the Finder does.
    @Test func theSubtitleIsTheAbbreviatedContainingDirectory() {
        let home = NSHomeDirectory()
        let subtitle = SpotlightQuery.subtitle(
            for: URL(filePath: "\(home)/Documents/report.pdf")
        )
        #expect(subtitle == "~/Documents")
    }
}
