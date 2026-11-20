import Foundation

public enum StorePathResolver {
    public static let envStorePath = "CLIPVOICE_STORE_PATH"

    public static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("ClipVoice", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    public static func resolve(cliArgument: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let arg = cliArgument, !arg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
        }
        if let env = environment[envStorePath], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return defaultStoreURL()
    }
}

public final class ClipStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var state: ClipStoreState
    private var lastLoadedModifiedAt: Date?

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public init(fileURL: URL = StorePathResolver.resolve()) {
        self.fileURL = fileURL
        self.state = ClipStoreState()
        try? loadFromDiskIfPresent()
    }

    public func currentState() -> ClipStoreState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func reloadIfChangedOnDisk() {
        lock.lock()
        defer { lock.unlock() }
        reloadIfChangedLocked()
    }

    public func list(kind: ClipKind? = nil, query: String? = nil, limit: Int? = nil) -> [ClipItem] {
        lock.lock()
        defer { lock.unlock() }
        reloadIfChangedLocked()

        var results = state.items
        if let kind {
            results = results.filter { $0.kind == kind }
        }
        if let query {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty {
                results = results.filter { item in
                    item.id.lowercased().contains(trimmed)
                        || item.content.lowercased().contains(trimmed)
                        || (item.domain?.lowercased().contains(trimmed) ?? false)
                }
            }
        }
        if let limit, limit > 0, results.count > limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    public func get(idOrSpoken query: String) -> ClipItem? {
        lock.lock()
        defer { lock.unlock() }
        reloadIfChangedLocked()
        return SpeakableID.resolve(query, in: state.items)
    }

    public func latest(kind: ClipKind? = nil) -> ClipItem? {
        lock.lock()
        defer { lock.unlock() }
        reloadIfChangedLocked()
        if let kind {
            return state.items.first(where: { $0.kind == kind })
        }
        return state.items.first
    }

    @discardableResult
    public func ingest(_ rawText: String, now: Date = Date()) -> IngestResult {
        lock.lock()
        defer { lock.unlock() }

        guard !state.isPaused else {
            return .ignoredPaused
        }
        guard PasteboardPrivacyFilter.isAllowedPayloadSize(rawText),
              let classification = ClipClassifier.classify(rawText) else {
            return .ignoredInvalidOrTooLarge
        }

        // Deduplicate by exact normalized content while preserving its stable ID
        // and moving it to the top (newest-first).
        if let existingIndex = state.items.firstIndex(where: { $0.content == classification.normalizedContent }) {
            var existing = state.items.remove(at: existingIndex)
            existing.updatedAt = now
            state.items.insert(existing, at: 0)
            persistLocked()
            return .bumpedExisting(existing)
        }

        let seq = state.nextSequence
        state.nextSequence += 1
        let newItem = ClipItem(
            id: SpeakableID.makeID(sequence: seq),
            sequence: seq,
            kind: classification.kind,
            content: classification.normalizedContent,
            domain: classification.domain,
            createdAt: now,
            updatedAt: now
        )
        state.items.insert(newItem, at: 0)
        trimToMaxItemsLocked()
        persistLocked()
        return .inserted(newItem)
    }

    @discardableResult
    public func bumpToTop(id: String, now: Date = Date()) -> ClipItem? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = state.items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var item = state.items.remove(at: index)
        item.updatedAt = now
        state.items.insert(item, at: 0)
        persistLocked()
        return item
    }

    @discardableResult
    public func delete(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let before = state.items.count
        state.items.removeAll { $0.id == id }
        let removed = state.items.count != before
        if removed {
            persistLocked()
        }
        return removed
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        state.items.removeAll()
        persistLocked()
    }

    public func setPaused(_ paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard state.isPaused != paused else { return }
        state.isPaused = paused
        persistLocked()
    }

    public func setMaxItems(_ maxItems: Int) {
        lock.lock()
        defer { lock.unlock() }
        state.maxItems = ClipStoreState.clampMaxItems(maxItems)
        trimToMaxItemsLocked()
        persistLocked()
    }

    // MARK: - Persistence Helpers

    private func trimToMaxItemsLocked() {
        if state.items.count > state.maxItems {
            state.items = Array(state.items.prefix(state.maxItems))
        }
    }

    private func loadFromDiskIfPresent() throws {
        lock.lock()
        defer { lock.unlock() }
        reloadIfChangedLocked(force: true)
    }

    private func reloadIfChangedLocked(force: Bool = false) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            if force {
                state = ClipStoreState()
            }
            return
        }

        let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
        let modDate = attrs?[.modificationDate] as? Date
        if !force, let modDate, let lastLoadedModifiedAt, modDate <= lastLoadedModifiedAt {
            return
        }

        // Retry briefly in case another process just performed an atomic rename.
        for attempt in 0..<3 {
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? decoder.decode(ClipStoreState.self, from: data) {
                var sanitized = decoded
                sanitized.maxItems = ClipStoreState.clampMaxItems(decoded.maxItems)
                sanitized.nextSequence = max(1, decoded.nextSequence)
                if sanitized.items.count > sanitized.maxItems {
                    sanitized.items = Array(sanitized.items.prefix(sanitized.maxItems))
                }
                state = sanitized
                lastLoadedModifiedAt = modDate ?? Date()
                return
            }
            if attempt < 2 {
                Thread.sleep(forTimeInterval: 0.015)
            }
        }
    }

    private func persistLocked() {
        let fm = FileManager.default
        let parent = fileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [
                .posixPermissions: NSNumber(value: Int16(0o700))
            ])
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
            try? fm.setAttributes([
                .posixPermissions: NSNumber(value: Int16(0o600))
            ], ofItemAtPath: fileURL.path)
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            lastLoadedModifiedAt = attrs?[.modificationDate] as? Date ?? Date()
        } catch {
            // Best effort local persistence; avoid crashing background monitor.
            FileHandle.standardError.write(Data("ClipVoice store write error: \(error.localizedDescription)\n".utf8))
        }
    }
}
