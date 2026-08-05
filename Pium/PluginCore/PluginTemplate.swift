import Foundation

/// One piece of an argument: text the author wrote, or the user's input.
enum PluginTemplateToken: Sendable, Equatable {
    case literal(String)
    case input(PluginTemplateFilter)
}

/// How the user's input is transformed before it reaches the argument.
enum PluginTemplateFilter: String, Sendable, Equatable, CaseIterable {
    case raw
    case urlEncode = "url_encode"
}

/// Parses `{{input}}` and `{{input|url_encode}}` into tokens.
///
/// Tokens rather than string replacement: an argument is built by concatenating
/// resolved tokens into one `argv` element, so nothing the user types can ever
/// become a separate argument or reach a shell. Phase 5 resolves them; this
/// phase only proves a template is well formed, which validation needs.
enum PluginTemplate {
    private static let opening = "{{"
    private static let closing = "}}"
    private static let variableName = "input"

    static func parse(_ string: String) -> Result<[PluginTemplateToken], PluginDiagnostic> {
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
            switch token(from: body) {
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
        from body: Substring
    ) -> Result<PluginTemplateToken, PluginDiagnostic> {
        let parts = body.split(separator: "|", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let name = parts.first, name == variableName else {
            return .failure(.invalidTemplate(
                String(localized: "plugin.template.unknownVariable \(String(body).trimmingCharacters(in: .whitespaces))")
            ))
        }

        guard parts.count == 2 else { return .success(.input(.raw)) }
        guard let filter = PluginTemplateFilter(rawValue: parts[1]) else {
            return .failure(.invalidTemplate(
                String(localized: "plugin.template.unknownFilter \(parts[1])")
            ))
        }
        return .success(.input(filter))
    }
}

/// So a `Result` failure can be thrown from tests and callers alike.
extension PluginDiagnostic: Error {}
