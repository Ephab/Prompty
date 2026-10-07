import Foundation

/// A `{{name}}` (or optional `{name}`) slot in a prompt body.
struct PromptVariable: Hashable, Sendable {
    var name: String
    var defaultValue: String?
}

enum PromptSegment: Hashable, Sendable {
    case text(String)
    case variable(PromptVariable, token: String)
}

struct Prompt: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    /// Position among favorites. `nil` for older libraries, which fall back to creation order.
    var favoriteOrder: Int?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        isFavorite: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        favoriteOrder: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
        self.favoriteOrder = favoriteOrder
    }

    /// The user preference for treating `{name}` as a variable in addition to `{{name}}`.
    static let singleBraceDefaultsKey = "prompty.singleBraceVariables"

    static var allowsSingleBraceVariables: Bool {
        UserDefaults.standard.bool(forKey: singleBraceDefaultsKey)
    }

    // `{{ name }}` or `{{ name : default }}`.
    private static let doubleBraceRegex = try! NSRegularExpression(
        pattern: #"\{\{\s*([^{}:]+?)\s*(?::\s*([^{}]*?)\s*)?\}\}"#
    )
    // `{name}` that is not part of `{{…}}`.
    private static let singleBraceRegex = try! NSRegularExpression(
        pattern: #"(?<!\{)\{([A-Za-z0-9_-]+)\}(?!\})"#
    )

    /// Ordered unique variable names detected in the prompt body.
    var placeholders: [String] {
        variables(allowSingleBraces: Self.allowsSingleBraceVariables).map(\.name)
    }

    func variables(allowSingleBraces: Bool) -> [PromptVariable] {
        var seen = Set<String>()
        var result: [PromptVariable] = []
        for match in Self.matches(in: body, allowSingleBraces: allowSingleBraces) {
            guard !seen.contains(match.variable.name) else { continue }
            seen.insert(match.variable.name)
            result.append(match.variable)
        }
        return result
    }

    /// Replaces each variable with its value. Empty values fall back to the
    /// variable's default; variables without a value or default are left as-is.
    func interpolatedBody(with values: [String: String]) -> String {
        interpolatedBody(with: values, allowSingleBraces: Self.allowsSingleBraceVariables)
    }

    func interpolatedBody(with values: [String: String], allowSingleBraces: Bool) -> String {
        let result = NSMutableString(string: body)
        let matches = Self.matches(in: body, allowSingleBraces: allowSingleBraces)
        for match in matches.reversed() {
            let value = values[match.variable.name]
            let replacement: String
            if let value, !value.isEmpty {
                replacement = value
            } else if let defaultValue = match.variable.defaultValue {
                replacement = defaultValue
            } else if let value {
                replacement = value
            } else {
                continue
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    /// Ranges of every variable token, in body order. Used for highlighting.
    func variableRanges(allowSingleBraces: Bool = Prompt.allowsSingleBraceVariables) -> [Range<String.Index>] {
        Self.matches(in: body, allowSingleBraces: allowSingleBraces).compactMap { Range($0.range, in: body) }
    }

    static func variableNSRanges(in text: String, allowSingleBraces: Bool = Prompt.allowsSingleBraceVariables) -> [NSRange] {
        matches(in: text, allowSingleBraces: allowSingleBraces).map(\.range)
    }

    /// The body split into literal text and variable tokens, for rendering previews.
    func segments(allowSingleBraces: Bool = Prompt.allowsSingleBraceVariables) -> [PromptSegment] {
        let nsBody = body as NSString
        var segments: [PromptSegment] = []
        var cursor = 0
        for match in Self.matches(in: body, allowSingleBraces: allowSingleBraces) {
            if match.range.location > cursor {
                segments.append(.text(nsBody.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            segments.append(.variable(match.variable, token: nsBody.substring(with: match.range)))
            cursor = match.range.location + match.range.length
        }
        if cursor < nsBody.length {
            segments.append(.text(nsBody.substring(from: cursor)))
        }
        return segments
    }

    /// A rough token estimate (≈ 4 characters per token) for display only.
    var approximateTokenCount: Int {
        Self.approximateTokenCount(for: body)
    }

    static func approximateTokenCount(for text: String) -> Int {
        text.isEmpty ? 0 : max(1, Int((Double(text.count) / 4).rounded()))
    }

    /// A title derived from the first non-empty line of a body, for drafts saved without one.
    static func derivedTitle(from body: String) -> String {
        let line = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        guard line.count > 60 else { return line }
        return String(line.prefix(59)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private struct VariableMatch {
        var range: NSRange
        var variable: PromptVariable
    }

    private static func matches(in text: String, allowSingleBraces: Bool) -> [VariableMatch] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var found: [VariableMatch] = doubleBraceRegex.matches(in: text, range: fullRange).compactMap { match in
            let name = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let defaultRange = match.range(at: 2)
            let defaultValue = defaultRange.location == NSNotFound ? nil : nsText.substring(with: defaultRange)
            return VariableMatch(range: match.range, variable: PromptVariable(name: name, defaultValue: defaultValue))
        }
        if allowSingleBraces {
            found += singleBraceRegex.matches(in: text, range: fullRange).map { match in
                VariableMatch(
                    range: match.range,
                    variable: PromptVariable(name: nsText.substring(with: match.range(at: 1)), defaultValue: nil)
                )
            }
            found.sort { $0.range.location < $1.range.location }
        }
        return found
    }

    static let samplePrompts: [Prompt] = [
        Prompt(
            title: "Code Review Assistant",
            body: "Review this {{language}} code for {{focus_area:security, performance and readability}}. Suggest concrete improvements with diffs where applicable:\n\n{{code}}",
            isFavorite: true,
            favoriteOrder: 0
        ),
        Prompt(
            title: "Executive Summary",
            body: "Provide a clear executive summary of the following content in 3 bullet points, followed by key risks and recommended next actions:\n\n{{clipboard}}",
            isFavorite: true,
            favoriteOrder: 1
        ),
        Prompt(
            title: "Draft Polished Email",
            body: "Draft a polite, professional, and concise email to {{recipient}} regarding {{topic}}. The key message to convey is:\n{{key_message}}",
            isFavorite: false
        ),
        Prompt(
            title: "Bug Report Formatter",
            body: "Format the following bug details into a clear engineering bug report with Steps to Reproduce, Expected Behavior, Actual Behavior, and Suspected Root Cause:\n\nIssue: {{issue_description}}",
            isFavorite: false
        )
    ]
}
