import Testing
import Foundation
@testable import Pium

@Suite("Plugin argument templates")
struct PluginTemplateTests {
    private func tokens(_ string: String) throws -> [PluginTemplateToken] {
        try PluginTemplate.parse(string).get()
    }

    @Test func plainTextIsOneLiteral() throws {
        #expect(try tokens("https://example.com") == [.literal("https://example.com")])
    }

    @Test func anEmptyStringHasNoTokens() throws {
        #expect(try tokens("").isEmpty)
    }

    @Test func aPlaceholderBecomesAnInputToken() throws {
        #expect(try tokens("{{input}}") == [.input(.raw)])
    }

    @Test func aFilterIsCarriedOnTheToken() throws {
        #expect(try tokens("{{input|url_encode}}") == [.input(.urlEncode)])
    }

    @Test func literalsAndPlaceholdersInterleave() throws {
        #expect(
            try tokens("https://x.com/?q={{input|url_encode}}&safe=1") == [
                .literal("https://x.com/?q="),
                .input(.urlEncode),
                .literal("&safe=1"),
            ]
        )
    }

    /// Whitespace inside the braces is what a human writes by accident, and
    /// rejecting it would be pedantry rather than safety.
    @Test func whitespaceInsideThePlaceholderIsTolerated() throws {
        #expect(try tokens("{{ input | url_encode }}") == [.input(.urlEncode)])
    }

    /// An unclosed placeholder means the author expected substitution that
    /// would never happen — silently treating it as a literal would ship a
    /// broken command.
    @Test func anUnclosedPlaceholderIsRejected() {
        #expect(throws: PluginDiagnostic.self) { try PluginTemplate.parse("a {{input").get() }
    }

    @Test func anUnknownFilterIsRejected() {
        #expect(throws: PluginDiagnostic.self) {
            try PluginTemplate.parse("{{input|base64}}").get()
        }
    }

    /// v1 has exactly one argument. Anything else is a typo the author must see.
    @Test func anUnknownVariableIsRejected() {
        #expect(throws: PluginDiagnostic.self) {
            try PluginTemplate.parse("{{clipboard}}").get()
        }
    }

    @Test func aRejectedTemplateSaysWhy() {
        guard case .failure(let diagnostic) = PluginTemplate.parse("{{input|base64}}") else {
            Issue.record("An unknown filter must be rejected")
            return
        }
        #expect(diagnostic.message.contains("base64"))
    }
}
