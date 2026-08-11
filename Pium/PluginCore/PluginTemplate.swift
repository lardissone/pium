import Foundation

/// One piece of an argument: text the author wrote, the user's input, or a
/// value the plugin declares in its configuration.
enum PluginTemplateToken: Sendable, Equatable {
    case literal(String)
    case input(PluginTemplateFilter)
    case configuration(String, PluginTemplateFilter)
}

/// How the user's input is transformed before it reaches the argument.
enum PluginTemplateFilter: String, Sendable, Equatable, CaseIterable {
    case raw
    case urlEncode = "url_encode"
}

/// Parses `{{input}}` and `{{input|url_encode}}` into tokens, and resolves
/// them into arguments.
///
/// Tokens rather than string replacement: an argument is built by concatenating
/// resolved tokens into one `argv` element, so nothing the user types can ever
/// become a separate argument or reach a shell. Validation proves a template is
/// well formed; execution resolves the tokens.
enum PluginTemplate {
    private static let opening = "{{"
    private static let closing = "}}"
    private static let variableName = "input"

    /// Names a configuration field may not take. `{{input}}` is classified as
    /// the plugin's own input before the declared keys are consulted, so a
    /// field by that name is unreachable — and a secret by that name would
    /// never become a `.configuration` token for the secret-in-arguments guard
    /// to catch. Rejecting the name is what keeps that guard whole.
    static let reservedVariableNames: Set<String> = [variableName]

    /// Arguments may also interpolate a value the manifest declares, so
    /// validation parses them with the configuration's keys in hand.
    static func parseAllowingConfiguration(
        _ string: String,
        configurationKeys: Set<String>
    ) -> Result<[PluginTemplateToken], PluginDiagnostic> {
        parse(string, extraVariables: configurationKeys)
    }

    static func parse(
        _ string: String,
        extraVariables: Set<String> = []
    ) -> Result<[PluginTemplateToken], PluginDiagnostic> {
        var tokens: [PluginTemplateToken] = []
        var remainder = Substring(string)

        while let start = remainder.range(of: opening) {
            let literal = remainder[remainder.startIndex..<start.lowerBound]
            if !literal.isEmpty { tokens.append(.literal(String(literal))) }

            let afterOpening = remainder[start.upperBound...]
            guard let end = afterOpening.range(of: closing) else {
                return .failure(.invalidTemplate(
                    String(localized: "plugin.template.unclosed \(string)")
                ))
            }

            let body = afterOpening[afterOpening.startIndex..<end.lowerBound]
            switch token(from: body, extraVariables: extraVariables) {
            case .success(let token): tokens.append(token)
            case .failure(let diagnostic): return .failure(diagnostic)
            }

            remainder = afterOpening[end.upperBound...]
        }

        if !remainder.isEmpty { tokens.append(.literal(String(remainder))) }
        return .success(tokens)
    }

    /// Turns the text between the braces into a token.
    private static func token(
        from body: Substring,
        extraVariables: Set<String>
    ) -> Result<PluginTemplateToken, PluginDiagnostic> {
        let parts = body.split(separator: "|", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let name = parts.first,
              name == variableName || extraVariables.contains(name)
        else {
            return .failure(.invalidTemplate(
                String(localized: "plugin.template.unknownVariable \(String(body).trimmingCharacters(in: .whitespaces))")
            ))
        }

        let filter: PluginTemplateFilter
        if parts.count == 2 {
            guard let named = PluginTemplateFilter(rawValue: parts[1]) else {
                return .failure(.invalidTemplate(
                    String(localized: "plugin.template.unknownFilter \(parts[1])")
                ))
            }
            filter = named
        } else {
            filter = .raw
        }

        return .success(name == variableName ? .input(filter) : .configuration(name, filter))
    }

    /// Concatenates resolved tokens into exactly one `argv` element.
    ///
    /// One element, always: an argument is a single string no matter what the
    /// user typed, so nothing can split itself into a second argument and
    /// nothing reaches a shell. A configuration key with no stored value
    /// resolves to nothing, never to the template text — a command receiving
    /// the literal `{{baseURL}}` is worse than one receiving an empty string.
    ///
    /// Secrets never appear here: `ManifestValidator` rejects a manifest that
    /// interpolates one, so a `.configuration` token naming a secret cannot
    /// reach this function.
    static func resolve(
        _ tokens: [PluginTemplateToken],
        input: String,
        configuration: [String: String]
    ) -> String {
        tokens.map { token in
            switch token {
            case .literal(let text):
                text
            case .input(let filter):
                apply(filter, to: input)
            case .configuration(let key, let filter):
                apply(filter, to: configuration[key] ?? "")
            }
        }
        .joined()
    }

    private static func apply(_ filter: PluginTemplateFilter, to value: String) -> String {
        switch filter {
        case .raw:
            value
        case .urlEncode:
            // The query-allowed set still permits `&` and `+`, which change the
            // meaning of the query they land in, so the allowed set is spelled
            // out as RFC 3986's unreserved characters.
            //
            // Written over UTF-8 bytes rather than through
            // `addingPercentEncoding`, whose `String?` return exists only
            // because it is bridged from `NSString` and cannot be nil for a
            // Swift string. That Optional forces a fallback, and the only
            // fallback available — the value unescaped — is precisely the
            // outcome this filter exists to prevent.
            percentEncoded(value)
        }
    }

    /// RFC 3986's unreserved set, kept; every other byte percent-encoded.
    ///
    /// Encoding runs over UTF-8 bytes rather than characters, which is what
    /// the escape is defined in terms of: one accented letter becomes two
    /// escapes, not one.
    private static func percentEncoded(_ value: String) -> String {
        let unreserved = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8
        )
        let hex = Array("0123456789ABCDEF".utf8)
        var encoded: [UInt8] = []
        for byte in value.utf8 {
            if unreserved.contains(byte) {
                encoded.append(byte)
            } else {
                encoded.append(contentsOf: [
                    UInt8(ascii: "%"), hex[Int(byte >> 4)], hex[Int(byte & 0x0F)],
                ])
            }
        }
        return String(decoding: encoded, as: UTF8.self)
    }
}

/// So a `Result` failure can be thrown from tests and callers alike.
extension PluginDiagnostic: Error {}
