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

    @Test func noDiagnosticMessageIsEmpty() {
        let all: [PluginDiagnostic] = [
            .unreadableFile,
            .malformedJSON("unexpected end of input"),
            .unknownKey(path: "", key: "x"),
            .missingKey("id"),
            .wrongType(path: "timeoutSeconds", expected: "integer"),
            .unsupportedSchemaVersion(99),
            .invalidIdentifier("X"),
            .invalidConfigurationKey("X"),
            .duplicateConfigurationKey("x"),
            .invalidTemplate("unclosed {{"),
            .secretInArguments(key: "token"),
            .invalidTimeout(0),
            .duplicateIdentifier("a"),
            .conflictingAlias("a"),
        ]
        for diagnostic in all {
            #expect(!diagnostic.message.isEmpty)
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
