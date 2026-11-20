import Foundation

public enum ClipVoiceVersion {
    public static let current = "0.1.1-beta"
    public static let bundleIdentifier = "dev.workromancer.clipvoice"
    public static let schemaVersion = 1
}

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case url
    case text
}

public enum ClipFilter: String, CaseIterable, Sendable {
    case all
    case url
    case text

    public var clipKind: ClipKind? {
        switch self {
        case .all: return nil
        case .url: return .url
        case .text: return .text
        }
    }
}

public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sequence: Int
    public let kind: ClipKind
    public let content: String
    public let domain: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        sequence: Int,
        kind: ClipKind,
        content: String,
        domain: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.content = content
        self.domain = domain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var charCount: Int {
        content.count
    }

    public var lineCount: Int {
        guard !content.isEmpty else { return 0 }
        return content.components(separatedBy: .newlines).count
    }

    public var preview: String {
        let collapsed = content
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if collapsed.count <= 140 {
            return collapsed
        }
        let endIdx = collapsed.index(collapsed.startIndex, offsetBy: 137)
        return String(collapsed[..<endIdx]) + "..."
    }

    /// Speakable prompt suggestion for voice-mode workflows.
    public var voiceHint: String {
        id.replacingOccurrences(of: "-", with: " ")
    }
}

public struct ClipStoreState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var nextSequence: Int
    public var isPaused: Bool
    public var maxItems: Int
    public var items: [ClipItem]

    public init(
        schemaVersion: Int = ClipVoiceVersion.schemaVersion,
        nextSequence: Int = 1,
        isPaused: Bool = false,
        maxItems: Int = 50,
        items: [ClipItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.nextSequence = max(1, nextSequence)
        self.isPaused = isPaused
        self.maxItems = ClipStoreState.clampMaxItems(maxItems)
        self.items = items
    }

    public static func clampMaxItems(_ value: Int) -> Int {
        min(max(value, 5), 200)
    }
}

public enum IngestResult: Equatable, Sendable {
    case inserted(ClipItem)
    case bumpedExisting(ClipItem)
    case ignoredPaused
    case ignoredInvalidOrTooLarge
}
