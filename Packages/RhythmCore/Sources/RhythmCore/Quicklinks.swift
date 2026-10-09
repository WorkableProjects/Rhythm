import Foundation

/// The destination type of a Quicklink, inferred from its URL scheme.
public enum QuicklinkKind: String, CaseIterable, Codable, Sendable {
    /// An `https` (or `http`) website. Universal links are also `https` URLs and open the
    /// matching app when iOS associates it with the domain.
    case website
    /// A custom app URL scheme entered by the user, e.g. `music://`.
    case app
    /// A `shortcuts://` URL that asks the Shortcuts app to run or open a shortcut.
    case shortcut

    public var displayName: String {
        switch self {
        case .website: "Website"
        case .app: "App Link"
        case .shortcut: "Shortcut"
        }
    }

    public var defaultSymbolName: String {
        switch self {
        case .website: "safari"
        case .app: "app.badge"
        case .shortcut: "square.stack.3d.up"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = QuicklinkKind(rawValue: raw) ?? .app
    }
}

/// Optional grouping for Quicklinks.
public enum QuicklinkCategory: String, CaseIterable, Codable, Sendable {
    case school, study, utility, personal

    public var displayName: String { rawValue.capitalized }
}

/// A value-type Quicklink used for export/import and App Intents.
public struct QuicklinkDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var urlString: String
    public var kind: QuicklinkKind
    public var symbolName: String?
    public var category: QuicklinkCategory?
    public var note: String?
    public var isFavorite: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        kind: QuicklinkKind,
        symbolName: String? = nil,
        category: QuicklinkCategory? = nil,
        note: String? = nil,
        isFavorite: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.kind = kind
        self.symbolName = symbolName
        self.category = category
        self.note = note
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
    }
}

/// Why a Quicklink URL was rejected.
public enum QuicklinkURLError: Error, Hashable, Sendable {
    case empty
    case malformed
    /// No scheme was entered. `suggestion` is an `https://` version the user may accept;
    /// Rhythm never applies it silently.
    case missingScheme(suggestion: String?)
    case unsupportedScheme(String)
    case missingHost

    public var message: String {
        switch self {
        case .empty: "Enter a link."
        case .malformed: "This doesn’t look like a valid link."
        case .missingScheme: "Add a scheme such as https:// to the start of the link."
        case .unsupportedScheme(let scheme): "Links starting with \(scheme): aren’t supported."
        case .missingHost: "Website links need a domain, such as https://example.com."
        }
    }
}

/// A URL that passed validation.
public struct ValidatedQuicklinkURL: Hashable, Sendable {
    public var url: URL
    public var kind: QuicklinkKind
    /// Non-blocking advice, e.g. for insecure `http` links.
    public var warning: String?
}

/// Validates user-entered Quicklink destinations. Input is trimmed; schemes are never rewritten.
public enum QuicklinkURLValidator {
    /// Schemes that can execute code or read local files; never allowed.
    static let blockedSchemes: Set<String> = ["javascript", "data", "file", "about", "blob", "vbscript"]

    public static func validate(_ raw: String) -> Result<ValidatedQuicklinkURL, QuicklinkURLError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return .failure(.malformed) }

        guard let schemeEnd = trimmed.firstIndex(of: ":") else {
            return .failure(.missingScheme(suggestion: httpsSuggestion(for: trimmed)))
        }
        let scheme = String(trimmed[..<schemeEnd]).lowercased()
        guard isValidScheme(scheme) else {
            // "localhost:8080" or "example.com:443/path" style input.
            return .failure(.missingScheme(suggestion: httpsSuggestion(for: trimmed)))
        }
        guard !blockedSchemes.contains(scheme) else { return .failure(.unsupportedScheme(scheme)) }
        guard let url = URL(string: trimmed) else { return .failure(.malformed) }

        switch scheme {
        case "https", "http":
            guard let host = url.host, !host.isEmpty else { return .failure(.missingHost) }
            let warning = scheme == "http" ? "This link isn’t secure. Use https:// if the site supports it." : nil
            return .success(ValidatedQuicklinkURL(url: url, kind: .website, warning: warning))
        case "shortcuts":
            return .success(ValidatedQuicklinkURL(
                url: url,
                kind: .shortcut,
                warning: "iOS opens this in the Shortcuts app and may ask for confirmation."
            ))
        default:
            let rest = trimmed[trimmed.index(after: schemeEnd)...]
            guard !rest.isEmpty else { return .failure(.malformed) }
            return .success(ValidatedQuicklinkURL(
                url: url,
                kind: .app,
                warning: "This opens only if an app on this iPhone supports the link."
            ))
        }
    }

    /// RFC 3986 scheme: a letter followed by letters, digits, "+", "-" or ".".
    static func isValidScheme(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first, CharacterSet.letters.contains(first), first.isASCII else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789+-.")
        return scheme.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func httpsSuggestion(for input: String) -> String? {
        let candidate = "https://" + input
        guard let url = URL(string: candidate), let host = url.host, host.contains(".") else { return nil }
        return candidate
    }
}
