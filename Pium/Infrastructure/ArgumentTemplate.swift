import Foundation

/// One piece of an argument: text its author wrote, the user's input, or a
/// value the caller declares.
enum ArgumentTemplateToken: Sendable, Equatable {
    case literal(String)
    case input(ArgumentTemplateFilter)
    case variable(String, ArgumentTemplateFilter)
}

/// How the user's input is transformed before it reaches the argument.
enum ArgumentTemplateFilter: String, Sendable, Equatable, CaseIterable {
    case raw
    case urlEncode = "url_encode"
}

/// What can be wrong with a template, carried as data rather than as a
/// sentence.
///
/// Two callers word the same rejection differently — a plugin's diagnostic
/// names a file its author is editing, and reaches the result list — so the
/// wording belongs to each of them rather than here.
enum ArgumentTemplateError: Error, Sendable, Equatable {
    case unclosedPlaceholder(String)
    case unknownVariable(String)
    case unknownFilter(String)
}

/// Parses `{{input}}` and `{{input|url_encode}}` into tokens, and resolves
/// them into arguments.
///
/// Tokens rather than string replacement: an argument is built by concatenating
/// resolved tokens into one `argv` element, so nothing the user types can ever
/// become a separate argument or reach a shell. Validation proves a template is
/// well formed; execution resolves the tokens.
enum ArgumentTemplate {
    private static let opening = "{{"
    private static let closing = "}}"
    private static let variableName = "input"

    /// Names a caller's own variables may not take. `{{input}}` is classified
    /// as the user's input before the declared names are consulted, so a
    /// variable by that name is unreachable — and a plugin's secret by that
    /// name would never become a `.variable` token for the secret-in-arguments
    /// guard to catch. Rejecting the name is what keeps that guard whole.
    static let reservedVariableNames: Set<String> = [variableName]

    /// A template may also interpolate values the caller declares, so parsing
    /// takes their names in hand.
    ///
    /// `defaultFilter` is what a placeholder written without one means. It is
    /// the caller's policy rather than the parser's: text going into a URL has
    /// to be percent-encoded and text going into a file name must not be, and
    /// neither caller should have to make its users write the filter out. It
    /// also keeps `{{input}}` and `{{input|raw}}` distinguishable, which they
    /// would not be if a bare placeholder were resolved to `.raw` here.
    static func parse(
        _ string: String,
        variables: Set<String> = [],
        defaultFilter: ArgumentTemplateFilter = .raw
    ) -> Result<[ArgumentTemplateToken], ArgumentTemplateError> {
        var tokens: [ArgumentTemplateToken] = []
        var remainder = Substring(string)

        while let start = remainder.range(of: opening) {
            let literal = remainder[remainder.startIndex..<start.lowerBound]
            if !literal.isEmpty { tokens.append(.literal(String(literal))) }

            let afterOpening = remainder[start.upperBound...]
            guard let end = afterOpening.range(of: closing) else {
                return .failure(.unclosedPlaceholder(string))
            }

            let body = afterOpening[afterOpening.startIndex..<end.lowerBound]
            switch token(from: body, variables: variables, defaultFilter: defaultFilter) {
            case .success(let token): tokens.append(token)
            case .failure(let error): return .failure(error)
            }

            remainder = afterOpening[end.upperBound...]
        }

        if !remainder.isEmpty { tokens.append(.literal(String(remainder))) }
        return .success(tokens)
    }

    /// Turns the text between the braces into a token.
    private static func token(
        from body: Substring,
        variables: Set<String>,
        defaultFilter: ArgumentTemplateFilter
    ) -> Result<ArgumentTemplateToken, ArgumentTemplateError> {
        let parts = body.split(separator: "|", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let name = parts.first,
              name == variableName || variables.contains(name)
        else {
            return .failure(
                .unknownVariable(String(body).trimmingCharacters(in: .whitespaces))
            )
        }

        let filter: ArgumentTemplateFilter
        if parts.count == 2 {
            guard let named = ArgumentTemplateFilter(rawValue: parts[1]) else {
                return .failure(.unknownFilter(parts[1]))
            }
            filter = named
        } else {
            filter = defaultFilter
        }

        return .success(name == variableName ? .input(filter) : .variable(name, filter))
    }

    /// Concatenates resolved tokens into exactly one `argv` element.
    ///
    /// One element, always: an argument is a single string no matter what the
    /// user typed, so nothing can split itself into a second argument and
    /// nothing reaches a shell. A declared variable with no value resolves to
    /// nothing, never to the template text — a command receiving the literal
    /// `{{baseURL}}` is worse than one receiving an empty string.
    ///
    /// A plugin's secrets never appear here: `ManifestValidator` rejects a
    /// manifest that interpolates one, so a `.variable` token naming a secret
    /// cannot reach this function.
    static func resolve(
        _ tokens: [ArgumentTemplateToken],
        input: String,
        variables: [String: String] = [:]
    ) -> String {
        tokens.map { token in
            switch token {
            case .literal(let text):
                text
            case .input(let filter):
                apply(filter, to: input)
            case .variable(let name, let filter):
                apply(filter, to: variables[name] ?? "")
            }
        }
        .joined()
    }

    private static func apply(_ filter: ArgumentTemplateFilter, to value: String) -> String {
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
