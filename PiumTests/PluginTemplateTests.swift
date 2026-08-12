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

    /// `docs/plugin-format-v1.md` tells authors that spaces inside the braces
    /// are allowed, which makes it a promise rather than an implementation
    /// detail. Somebody writing a manifest by hand spaces things out.
    @Test func spacesInsideTheBracesAreAllowed() throws {
        #expect(try tokens("{{ input }}") == [.input(.raw)])
        #expect(try tokens("{{ input | url_encode }}") == [.input(.urlEncode)])
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

@Suite("Template resolution")
struct PluginTemplateResolutionTests {
    private func tokens(_ string: String, keys: Set<String> = []) throws -> [PluginTemplateToken] {
        try PluginTemplate.parseAllowingConfiguration(string, configurationKeys: keys).get()
    }

    @Test func literalsSurviveUntouched() throws {
        let resolved = PluginTemplate.resolve(
            try tokens("--flag"), input: "ignored", configuration: [:]
        )
        #expect(resolved == "--flag")
    }

    /// One argv element, whatever the input contains: the whole point of
    /// tokens over string replacement.
    @Test func inputWithSpacesStaysOneArgument() throws {
        let resolved = PluginTemplate.resolve(
            try tokens("{{input}}"), input: "hello world; rm -rf /", configuration: [:]
        )
        #expect(resolved == "hello world; rm -rf /")
    }

    @Test func theUrlEncodeFilterEncodesTheInput() throws {
        let resolved = PluginTemplate.resolve(
            try tokens("https://x.com/?q={{input|url_encode}}"),
            input: "a b&c",
            configuration: [:]
        )
        #expect(resolved == "https://x.com/?q=a%20b%26c")
    }

    @Test func aConfigurationValueIsInterpolated() throws {
        let resolved = PluginTemplate.resolve(
            try tokens("{{baseURL}}/status", keys: ["baseURL"]),
            input: "",
            configuration: ["baseURL": "https://home.local"]
        )
        #expect(resolved == "https://home.local/status")
    }

    /// A field the user never filled resolves to nothing rather than to the
    /// literal `{{baseURL}}`, which would reach the command as text.
    @Test func anUnfilledConfigurationValueResolvesToEmpty() throws {
        let resolved = PluginTemplate.resolve(
            try tokens("{{baseURL}}/status", keys: ["baseURL"]),
            input: "",
            configuration: [:]
        )
        #expect(resolved == "/status")
    }
}
