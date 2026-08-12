import Testing
import Foundation
@testable import Pium

/// Confronts what the app actually ships, the way `PluginSchemaAgreementTests`
/// confronts the shipped schema.
///
/// Deliberately reads the compiled `.lproj/Localizable.strings` inside the
/// bundle rather than the `Localizable.xcstrings` source. The source is what an
/// editor shows; these tables are what `String(localized:)` reaches at run
/// time, and a key that never made it through the build is invisible in the
/// former and missing from the latter.
///
/// PRD §15 promises English and Spanish. What breaks that promise is never a
/// decision — it is a key added in one language on the way to something else,
/// shipped before the other catches up. Care does not prevent that on a project
/// with one developer; a test does.
@Suite("Localization catalog")
struct LocalizationCatalogTests {
    /// The languages PRD §15 commits to.
    private static let required = ["en", "es"]

    private func table(_ language: String) throws -> [String: String] {
        let url = try #require(
            Bundle.main.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            ),
            "\(language) has no compiled string table in the bundle"
        )
        let contents = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(
            from: contents, format: nil
        )
        return try #require(parsed as? [String: String], "\(language)'s table is not a dictionary")
    }

    @Test func everyLanguageWePromiseIsShipped() throws {
        for language in Self.required {
            #expect(try !table(language).isEmpty)
        }
    }

    /// The failure this exists for: a key that reached English and not Spanish.
    @Test func everyKeyIsTranslatedIntoEveryLanguageWePromise() throws {
        let tables = try Self.required.map { ($0, try table($0)) }
        let everyKey = Set(tables.flatMap { $0.1.keys })

        for (language, table) in tables {
            let missing = everyKey.subtracting(table.keys).sorted()
            #expect(
                missing.isEmpty,
                "no \(language) value for: \(missing.joined(separator: ", "))"
            )
        }
    }

    /// A value identical to its own key is what `String(localized:)` hands back
    /// when nothing matches, and it reaches the screen looking like a bug
    /// nobody wrote. Keys carrying a format specifier are exempt: `about.version
    /// %@` is a key whose Spanish legitimately differs only by word order.
    @Test func nokeyIsShippedAsItsOwnName() throws {
        for language in Self.required {
            let echoed = try table(language)
                .filter { key, value in key == value && !key.contains("%") }
                .keys
                .sorted()
            #expect(
                echoed.isEmpty,
                "\(language) ships these as their own key: \(echoed.joined(separator: ", "))"
            )
        }
    }

    /// The tables have not silently shrunk. A floor rather than an equality:
    /// it fails on deletion, which is the accident worth catching, and never
    /// on an ordinary addition.
    @Test func thecatalogStillHoldsEverythingItHeld() throws {
        let atLeast = 174
        for language in Self.required {
            let count = try table(language).count
            #expect(
                count >= atLeast,
                "\(language) shrank to \(count) keys; something was removed rather than added"
            )
        }
    }
}
