import Foundation

public struct ClassificationResult: Equatable, Sendable {
    public let kind: ClipKind
    public let normalizedContent: String
    public let domain: String?

    public init(kind: ClipKind, normalizedContent: String, domain: String?) {
        self.kind = kind
        self.normalizedContent = normalizedContent
        self.domain = domain
    }
}

/// Classifies clipboard text into `.url` or `.text` purely locally without DNS or network calls.
public enum ClipClassifier {
    public static func classify(_ raw: String) -> ClassificationResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let urlInfo = parseSafeWebURL(from: trimmed) {
            return ClassificationResult(
                kind: .url,
                normalizedContent: trimmed,
                domain: urlInfo.domain
            )
        }

        return ClassificationResult(
            kind: .text,
            normalizedContent: raw,
            domain: nil
        )
    }

    private static func parseSafeWebURL(from candidate: String) -> (url: URL, domain: String)? {
        // Reject multiline strings or strings containing internal whitespace.
        guard candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }

        // Reject bare schemes or malformed hosts without letters/digits.
        guard host.rangeOfCharacter(from: .alphanumerics) != nil else {
            return nil
        }
        // Require a dot in host unless localhost / IPv6 literal.
        let lowerHost = host.lowercased()
        guard lowerHost == "localhost" || lowerHost.contains(".") || lowerHost.contains(":") else {
            return nil
        }

        let domainLabel: String
        if let port = components.port {
            domainLabel = "\(lowerHost):\(port)"
        } else {
            domainLabel = lowerHost
        }

        return (url, domainLabel)
    }
}
