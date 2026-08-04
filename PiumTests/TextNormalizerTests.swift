import Testing
@testable import Pium

@Suite("Text normalization")
struct TextNormalizerTests {
    /// Case and accents must never prevent a reasonable match. Spanish is a
    /// shipping language, so this is not a nicety.
    @Test(arguments: [
        ("Safari", "safari"),
        ("SAFARI", "safari"),
        ("Códigos", "codigos"),
        ("Añejo", "anejo"),
        ("  spaced   out  ", "spaced out"),
    ])
    func foldingRemovesCaseAccentsAndExtraWhitespace(input: String, expected: String) {
        #expect(TextNormalizer.fold(input) == expected)
    }

    /// Tokens are what "whole word" and "token prefix" scoring match against.
    @Test func tokenizationSplitsOnWhitespacePunctuationAndCamelCase() {
        #expect(TextNormalizer.tokenize("Visual Studio Code") == ["visual", "studio", "code"])
        #expect(TextNormalizer.tokenize("IINA") == ["iina"])
        #expect(TextNormalizer.tokenize("QuickTime Player") == ["quick", "time", "player"])
        #expect(TextNormalizer.tokenize("Adobe-Photoshop_2026") == ["adobe", "photoshop", "2026"])
    }

    /// Acronym matching is what makes "vsc" find "Visual Studio Code".
    @Test func acronymTakesTheFirstLetterOfEachToken() {
        #expect(TextNormalizer.candidate("Visual Studio Code").acronym == "vsc")
        #expect(TextNormalizer.candidate("QuickTime Player").acronym == "qtp")
        #expect(TextNormalizer.candidate("Safari").acronym == "s")
    }

    @Test func anEmptyQueryIsReportedAsEmpty() {
        #expect(TextNormalizer.query("").isEmpty)
        #expect(TextNormalizer.query("   ").isEmpty)
        #expect(!TextNormalizer.query("s").isEmpty)
    }

    /// The original string survives for display and for passing to plugins.
    @Test func theRawQueryIsPreserved() {
        #expect(TextNormalizer.query("  Café  ").raw == "  Café  ")
        #expect(TextNormalizer.query("  Café  ").folded == "cafe")
    }
}
