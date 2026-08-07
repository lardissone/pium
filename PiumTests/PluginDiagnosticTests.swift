import Testing
import Foundation
@testable import Pium

@Suite("Plugin diagnostics")
struct PluginDiagnosticTests {
    /// A diagnostic exists to be read by whoever has to fix the file, so it has
    /// to name the thing that is wrong.
    @Test func everyDiagnosticNamesWhatIsWrong() {
        #expect(PluginDiagnostic.unknownKey(path: "command", key: "shel").message.contains("shel"))
        #expect(PluginDiagnostic.missingKey("id").message.contains("id"))
        #expect(PluginDiagnostic.duplicateIdentifier("web.yt").message.contains("web.yt"))
        #expect(PluginDiagnostic.conflictingAlias("yt").message.contains("yt"))
        #expect(PluginDiagnostic.invalidIdentifier("Web YT").message.contains("Web YT"))
        #expect(PluginDiagnostic.secretInArguments(key: "token").message.contains("token"))
        #expect(PluginDiagnostic.invalidConfigurationKey("Token Key").message.contains("Token Key"))
        #expect(PluginDiagnostic.duplicateConfigurationKey("token").message.contains("token"))
    }

    /// A key the catalog has no entry for is not an error: `String(localized:)`
    /// hands back the key itself, which is non-empty and would satisfy any
    /// "has a message" check while the author reads `plugin.diagnostic.invalidTimeout 0`.
    /// So the bar is the rendered sentence: every key here lives under the
    /// `plugin.diagnostic.` namespace, and no rendered message does.
    @Test func everyDiagnosticRendersItsCatalogEntryAndNamesItsSubject() {
        let all: [(PluginDiagnostic, subject: String?)] = [
            (.unreadableFile, nil),
            (.malformedJSON("unexpected end of input"), "unexpected end of input"),
            (.unknownKey(path: "", key: "x"), "x"),
            (.missingKey("id"), "id"),
            (.wrongType(path: "timeoutSeconds", expected: "integer"), "timeoutSeconds"),
            (.unsupportedSchemaVersion(99), "99"),
            (.invalidIdentifier("X"), "X"),
            (.invalidConfigurationKey("X"), "X"),
            (.duplicateConfigurationKey("x"), "x"),
            (.invalidTemplate("unclosed {{"), "unclosed {{"),
            (.secretInArguments(key: "token"), "token"),
            (.invalidTimeout(0), "0"),
            (.duplicateIdentifier("a"), "a"),
            (.conflictingAlias("a"), "a"),
        ]
        for (diagnostic, subject) in all {
            let message = diagnostic.message
            #expect(
                !message.hasPrefix("plugin.diagnostic."),
                "\(diagnostic) shows its lookup key instead of a message: \(message)"
            )
            if let subject {
                #expect(
                    message.contains(subject),
                    "\(diagnostic) never names \(subject): \(message)"
                )
            }
        }
    }

    /// The version mismatch is the one an author hits after an upgrade, so it
    /// must name both numbers rather than only the offending one.
    @Test func theVersionMismatchNamesBothVersions() {
        let message = PluginDiagnostic.unsupportedSchemaVersion(99).message
        #expect(message.contains("99"))
        #expect(message.contains("\(PluginManifest.currentSchemaVersion)"))
    }
}
