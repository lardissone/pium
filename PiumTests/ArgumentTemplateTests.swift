import Testing
import Foundation
@testable import Pium

@Suite("Argument templates")
struct ArgumentTemplateTests {
    private func tokens(_ string: String) throws -> [ArgumentTemplateToken] {
        try ArgumentTemplate.parse(string).get()
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
        #expect(throws: ArgumentTemplateError.self) {
            try ArgumentTemplate.parse("a {{input").get()
        }
    }

    @Test func anUnknownFilterIsRejected() {
        #expect(throws: ArgumentTemplateError.self) {
            try ArgumentTemplate.parse("{{input|base64}}").get()
        }
    }

    /// One argument, and whatever variables the caller declares. Anything else
    /// is a typo its author must see.
    @Test func anUnknownVariableIsRejected() {
        #expect(throws: ArgumentTemplateError.self) {
            try ArgumentTemplate.parse("{{clipboard}}").get()
        }
    }

    /// The error carries what was wrong rather than a sentence about it. Two
    /// callers word a rejected template differently — a plugin's diagnostic
    /// names a file its author is editing — and neither wording belongs in a
    /// type both of them share.
    @Test func aRejectedTemplateCarriesTheOffendingText() {
        #expect(
            ArgumentTemplate.parse("{{input|base64}}").failure == .unknownFilter("base64")
        )
        #expect(
            ArgumentTemplate.parse("{{clipboard}}").failure == .unknownVariable("clipboard")
        )
        #expect(
            ArgumentTemplate.parse("a {{input").failure == .unclosedPlaceholder("a {{input")
        )
    }

    /// The name `input` always means the argument, so a caller cannot declare a
    /// variable that shadows it — the declaration would be unreachable, and a
    /// plugin's secret by that name would slip past the guard that keeps
    /// secrets out of an argument list.
    @Test func theArgumentsOwnNameIsReserved() {
        #expect(ArgumentTemplate.reservedVariableNames.contains("input"))
    }
}

@Suite("Argument template resolution")
struct ArgumentTemplateResolutionTests {
    private func tokens(
        _ string: String, variables: Set<String> = []
    ) throws -> [ArgumentTemplateToken] {
        try ArgumentTemplate.parse(string, variables: variables).get()
    }

    @Test func literalsSurviveUntouched() throws {
        let resolved = ArgumentTemplate.resolve(try tokens("--flag"), input: "ignored")
        #expect(resolved == "--flag")
    }

    /// One argv element, whatever the input contains: the whole point of
    /// tokens over string replacement.
    @Test func inputWithSpacesStaysOneArgument() throws {
        let resolved = ArgumentTemplate.resolve(
            try tokens("{{input}}"), input: "hello world; rm -rf /"
        )
        #expect(resolved == "hello world; rm -rf /")
    }

    @Test func theUrlEncodeFilterEncodesTheInput() throws {
        let resolved = ArgumentTemplate.resolve(
            try tokens("https://x.com/?q={{input|url_encode}}"), input: "a b&c"
        )
        #expect(resolved == "https://x.com/?q=a%20b%26c")
    }

    @Test func aDeclaredVariableIsInterpolated() throws {
        let resolved = ArgumentTemplate.resolve(
            try tokens("{{baseURL}}/status", variables: ["baseURL"]),
            input: "",
            variables: ["baseURL": "https://home.local"]
        )
        #expect(resolved == "https://home.local/status")
    }

    /// A variable the caller has no value for resolves to nothing rather than
    /// to the literal `{{baseURL}}`, which would reach the command as text.
    @Test func anUnfilledVariableResolvesToEmpty() throws {
        let resolved = ArgumentTemplate.resolve(
            try tokens("{{baseURL}}/status", variables: ["baseURL"]), input: ""
        )
        #expect(resolved == "/status")
    }
}

extension Result {
    /// The failure of a `Result`, for asserting on it without a `guard case`.
    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
