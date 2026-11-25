import Foundation

public enum ClipVoiceVersion {
    public static let current = "0.2.0-beta"
    public static let bundleIdentifier = "dev.workromancer.clipvoice"
    public static let schemaVersion = 2
}

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case url
    case text
    case image
}

public enum ClipFilter: String, CaseIterable, Sendable {
    case all
    case url
    case text
    case image

    public var clipKind: ClipKind? {
        switch self {
        case .all: return nil
        case .url: return .url
        case .text: return .text
        case .image: return .image
        }
    }
}

public struct ClipImageMetadata: Codable, Equatable, Sendable {
    public let assetFileName: String
    public let width: Int
    public let height: Int
    public let byteSize: Int
    public let sha256: String
    public let mimeType: String

    public init(
        assetFileName: String,
        width: Int,
        height: Int,
        byteSize: Int,
        sha256: String,
        mimeType: String = "image/png"
    ) {
        self.assetFileName = assetFileName
        self.width = width
        self.height = height
        self.byteSize = byteSize
        self.sha256 = sha256
        self.mimeType = mimeType
    }

    public var dimensionsLabel: String {
        "\(width)×\(height)"
    }

    public var formattedByteSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }
}

public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sequence: Int
    public let kind: ClipKind
    public let content: String
    public let domain: String?
    public let image: ClipImageMetadata?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        sequence: Int,
        kind: ClipKind,
        content: String,
        domain: String?,
        image: ClipImageMetadata? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.content = content
        self.domain = domain
        self.image = image
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
        if kind == .image, let image {
            return "Image \(image.dimensionsLabel) PNG · \(image.formattedByteSize)"
        }
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

    /// Preserves original line breaks and indentation for multi-line HUD previews.
    public func multilinePreview(maxCharacters: Int = 600) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.count <= maxCharacters {
            return normalized
        }
        let idx = normalized.index(normalized.startIndex, offsetBy: maxCharacters)
        return String(normalized[..<idx]) + "…"
    }

    /// Heuristic to render code/multiline snippets in monospaced font.
    public var prefersMonospacedPreview: Bool {
        if kind == .url { return true }
        if content.contains("\n") || content.contains("\t") { return true }
        let codeTokens = ["{", "}", "=>", "()", "SELECT ", "func ", "let ", "const ", "import ", "--", "./", "http://", "https://"]
        return codeTokens.contains(where: { content.contains($0) })
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
    case persistenceFailed
}

public enum AgentWriteOutcome: Equatable, Sendable {
    case inserted(ClipItem)
    case bumpedExisting(ClipItem)

    public var item: ClipItem {
        switch self {
        case .inserted(let item), .bumpedExisting(let item):
            return item
        }
    }

    public var isNew: Bool {
        if case .inserted = self { return true }
        return false
    }
}

public enum AgentWriteError: Error, LocalizedError, Equatable, Sendable {
    case emptyContent
    case payloadTooLarge(maxBytes: Int)
    case invalidImage(String)
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Cannot write empty or whitespace-only content to clipboard."
        case .payloadTooLarge(let maxBytes):
            return "Payload exceeds maximum allowed size (\(maxBytes) bytes)."
        case .invalidImage(let reason):
            return "Invalid or unsupported image: \(reason)"
        case .persistenceFailed(let reason):
            return "Failed to persist clipboard item: \(reason)"
        }
    }
}

public enum WindowPlacementMode: String, Codable, CaseIterable, Sendable {
    case dockLeft = "dock_left"
    case floating = "floating"
    case dockRight = "dock_right"
}
