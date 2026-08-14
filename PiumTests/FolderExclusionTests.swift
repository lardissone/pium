import Testing
import Foundation
@testable import Pium

@Suite("Folder exclusion")
struct FolderExclusionTests {
    // MARK: Storing what was typed

    /// A path pasted from a terminal or dragged onto the field arrives with
    /// stray whitespace as often as not.
    @Test func whitespaceAroundAnEntryIsDropped() {
        #expect(FolderExclusion.normalized("  node_modules  ") == "node_modules")
    }

    @Test func aTildeIsExpandedSoTheStoredEntryStandsOnItsOwn() {
        #expect(
            FolderExclusion.normalized("~/Developer/archive")
                == "\(NSHomeDirectory())/Developer/archive"
        )
    }

    /// The same folder stored twice, once with the slash and once without,
    /// reads as two entries that exclude exactly the same files.
    @Test func aTrailingSlashIsDropped() {
        #expect(FolderExclusion.normalized("/Users/someone/Downloads/") == "/Users/someone/Downloads")
    }

    @Test(arguments: ["", "   ", "\n"])
    func anEmptyEntryIsRefused(raw: String) {
        #expect(FolderExclusion.normalized(raw) == nil)
    }

    /// With a slash in it the entry is a path, and a relative path has no
    /// meaning here: there is nothing for it to be relative to.
    @Test func aRelativePathIsRefused() {
        #expect(FolderExclusion.normalized("Developer/pium") == nil)
    }

    /// A pattern is stored as typed. Expanding or tidying it would change what
    /// it matches.
    @Test(arguments: ["**/[Cc]ache/**", "*.tmp", "**/tmp/**"])
    func aPatternIsKeptAsWritten(raw: String) {
        #expect(FolderExclusion.normalized(raw) == raw)
    }

    // MARK: Matching by folder name

    @Test(arguments: [
        "/Users/someone/Projects/app/build/index.js",
        "/Users/someone/build/notes.md",
        "/Users/someone/a/b/c/build/deep/file.txt",
    ])
    func aBareNameExcludesThatFolderAtAnyDepth(path: String) {
        #expect(FolderExclusion.excludes(URL(filePath: path), matching: ["build"]))
    }

    /// A name matches a whole path component or nothing. Otherwise excluding
    /// `build` would take `rebuild-notes.md` with it.
    @Test(arguments: [
        "/Users/someone/Projects/rebuild/index.js",
        "/Users/someone/Documents/build-notes.md",
    ])
    func aBareNameDoesNotMatchPartOfAComponent(path: String) {
        #expect(!FolderExclusion.excludes(URL(filePath: path), matching: ["build"]))
    }

    // MARK: Matching by path

    @Test func aPathExcludesTheFolderAndEverythingUnderIt() {
        let entries = ["/Users/someone/Developer/archive"]
        #expect(FolderExclusion.excludes(URL(filePath: entries[0]), matching: entries))
        #expect(
            FolderExclusion.excludes(
                URL(filePath: "/Users/someone/Developer/archive/2019/taxes.pdf"),
                matching: entries
            )
        )
    }

    /// The trap in comparing paths as strings: `~/Dev` is a prefix of
    /// `~/Development`, and excluding the first must not empty the second.
    @Test func aPathDoesNotExcludeASiblingThatMerelyStartsTheSame() {
        #expect(
            !FolderExclusion.excludes(
                URL(filePath: "/Users/someone/Development/app/main.swift"),
                matching: ["/Users/someone/Dev"]
            )
        )
    }

    /// The picker offers files as well as folders, so a single file is an
    /// entry like any other.
    @Test func aFilePathExcludesThatOneFile() {
        #expect(
            FolderExclusion.excludes(
                URL(filePath: "/Volumes/Backup/old.dmg"),
                matching: ["/Volumes/Backup/old.dmg"]
            )
        )
    }

    // MARK: Matching by pattern

    @Test(arguments: [
        ("*.tmp", "/Users/someone/Documents/draft.tmp"),
        ("**/tmp/**", "/Users/someone/Projects/app/tmp/build.log"),
        ("**/[Cc]ache/**", "/Users/someone/Projects/app/Cache/data.bin"),
        ("**/[Cc]ache/**", "/Users/someone/Projects/app/cache/data.bin"),
        ("/Users/someone/*/secrets/*", "/Users/someone/work/secrets/keys.txt"),
    ])
    func aPatternExcludesWhatItMatches(pattern: String, path: String) {
        #expect(FolderExclusion.excludes(URL(filePath: path), matching: [pattern]))
    }

    @Test(arguments: [
        ("*.tmp", "/Users/someone/Documents/draft.txt"),
        ("**/tmp/**", "/Users/someone/Projects/app/src/main.swift"),
        ("**/[Cc]ache/**", "/Users/someone/Projects/app/caches/data.bin"),
    ])
    func aPatternLeavesEverythingElseAlone(pattern: String, path: String) {
        #expect(!FolderExclusion.excludes(URL(filePath: path), matching: [pattern]))
    }

    // MARK: Everything together

    /// The default: nothing excluded, nothing to do.
    @Test func nothingIsExcludedWhenTheListIsEmpty() {
        #expect(!FolderExclusion.excludes(URL(filePath: "/Users/someone/x.txt"), matching: []))
    }

    /// One entry is enough; the rest do not have to agree.
    @Test func anyEntryIsEnoughToExclude() {
        #expect(
            FolderExclusion.excludes(
                URL(filePath: "/Users/someone/Projects/app/build/x.o"),
                matching: ["/nowhere", "*.zzz", "build"]
            )
        )
    }

    /// The volume Pium searches treats `Build` and `build` as the same folder,
    /// so an exclusion that did not would appear to be ignored at random.
    @Test(arguments: [
        ("build", "/Users/someone/Projects/app/Build/x.o"),
        ("/Users/someone/Developer", "/Users/someone/developer/app/main.swift"),
        ("*.TMP", "/Users/someone/Documents/draft.tmp"),
    ])
    func matchingIgnoresCaseTheWayTheFilesystemDoes(entry: String, path: String) {
        #expect(FolderExclusion.excludes(URL(filePath: path), matching: [entry]))
    }
}
