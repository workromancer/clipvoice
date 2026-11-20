import Foundation

public enum MCPActivityOperation: String, Codable, Sendable {
    case listClips = "list_clips"
    case getClip = "get_clip"
    case searchClips = "search_clips"
    case getLatestClip = "get_latest_clip"
    case readResource = "resources/read"

    public var localizationKey: String {
        switch self {
        case .listClips: return "mcp.op.list_clips"
        case .getClip: return "mcp.op.get_clip"
        case .searchClips: return "mcp.op.search_clips"
        case .getLatestClip: return "mcp.op.get_latest_clip"
        case .readResource: return "mcp.op.resources_read"
        }
    }
}

/// Sanitized local-only signal emitted when MCP reads clipboard data.
/// Contains zero clipboard content, queries, or item IDs.
public struct MCPActivityEvent: Codable, Equatable, Sendable {
    public let eventID: String
    public let operation: MCPActivityOperation
    public let timestamp: Date

    public init(eventID: String = UUID().uuidString, operation: MCPActivityOperation, timestamp: Date = Date()) {
        self.eventID = eventID
        self.operation = operation
        self.timestamp = timestamp
    }
}

public enum MCPActivitySignal {
    public static let notificationName = Notification.Name("dev.workromancer.clipvoice.mcpActivity")

    public static func activityFileURL(for storeFileURL: URL) -> URL {
        let standardized = storeFileURL.standardizedFileURL
        return URL(fileURLWithPath: standardized.path + ".mcp-activity", isDirectory: false)
    }

    public static func storeIdentifier(for storeFileURL: URL) -> String {
        storeFileURL.standardizedFileURL.path
    }

    // Encode exact Double epoch seconds so sub-second ordering is never truncated.
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .secondsSince1970
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let isoString = try container.decode(String.self)
            let fractionalISO = ISO8601DateFormatter()
            fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalISO.date(from: isoString) {
                return date
            }
            let basicISO = ISO8601DateFormatter()
            basicISO.formatOptions = [.withInternetDateTime]
            if let date = basicISO.date(from: isoString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid MCPActivityEvent timestamp")
        }
        return dec
    }()

    public static func emit(operation: MCPActivityOperation, storeFileURL: URL, now: Date = Date()) {
        let event = MCPActivityEvent(eventID: UUID().uuidString, operation: operation, timestamp: now)
        let signalURL = activityFileURL(for: storeFileURL)
        let fm = FileManager.default

        do {
            try fm.createDirectory(
                at: signalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            let data = try encoder.encode(event)
            try data.write(to: signalURL, options: [.atomic])
            try? fm.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: signalURL.path
            )
        } catch {
            // Best effort: missing directory permissions should never crash MCP responses.
        }

        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: storeIdentifier(for: storeFileURL),
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public static func readLatest(for storeFileURL: URL) -> MCPActivityEvent? {
        let signalURL = activityFileURL(for: storeFileURL)
        guard FileManager.default.fileExists(atPath: signalURL.path),
              let data = try? Data(contentsOf: signalURL),
              let event = try? decoder.decode(MCPActivityEvent.self, from: data) else {
            return nil
        }
        return event
    }
}

/// Stateful watermark preventing stale pre-launch MCP markers while preserving sub-second fresh accesses.
public final class MCPActivityWatermark: @unchecked Sendable {
    public let storeFileURL: URL
    public let startupTimestamp: Date
    private var lastHandledEventID: String?
    private let lock = NSLock()

    public init(storeFileURL: URL, now: Date = Date()) {
        self.storeFileURL = storeFileURL
        self.startupTimestamp = now
        if let existing = MCPActivitySignal.readLatest(for: storeFileURL) {
            self.lastHandledEventID = existing.eventID
        }
    }

    public func poll() -> MCPActivityEvent? {
        guard let event = MCPActivitySignal.readLatest(for: storeFileURL) else {
            return nil
        }
        return acceptIfFresh(event)
    }

    public func acceptIfFresh(_ event: MCPActivityEvent) -> MCPActivityEvent? {
        lock.lock()
        defer { lock.unlock() }

        guard event.eventID != lastHandledEventID else {
            return nil
        }
        guard event.timestamp >= startupTimestamp else {
            lastHandledEventID = event.eventID
            return nil
        }
        lastHandledEventID = event.eventID
        return event
    }
}
