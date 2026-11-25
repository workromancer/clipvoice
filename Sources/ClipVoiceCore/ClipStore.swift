import Foundation
import Darwin

@_silgen_name("flock")
private func c_flock(_ fd: Int32, _ operation: Int32) -> Int32

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
    public let imageAssets: ImageAssetStore
    private let lockFileURL: URL
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
        self.fileURL = fileURL.standardizedFileURL
        self.imageAssets = ImageAssetStore(storeFileURL: self.fileURL)
        self.lockFileURL = URL(fileURLWithPath: self.fileURL.path + ".lock", isDirectory: false)
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
        withFileLock(exclusive: false) {
            reloadIfChangedLocked()
        }
    }

    public func list(kind: ClipKind? = nil, query: String? = nil, limit: Int? = nil) -> [ClipItem] {
        lock.lock()
        defer { lock.unlock() }
        withFileLock(exclusive: false) {
            reloadIfChangedLocked()
        }

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
                        || (item.image?.dimensionsLabel.lowercased().contains(trimmed) ?? false)
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
        withFileLock(exclusive: false) {
            reloadIfChangedLocked()
        }
        return SpeakableID.resolve(query, in: state.items)
    }

    public func latest(kind: ClipKind? = nil) -> ClipItem? {
        lock.lock()
        defer { lock.unlock() }
        withFileLock(exclusive: false) {
            reloadIfChangedLocked()
        }
        if let kind {
            return state.items.first(where: { $0.kind == kind })
        }
        return state.items.first
    }

    @discardableResult
    public func ingest(_ rawText: String, now: Date = Date()) -> IngestResult {
        lock.lock()
        defer { lock.unlock() }

        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)

            guard !state.isPaused else {
                return .ignoredPaused
            }
            guard PasteboardPrivacyFilter.isAllowedPayloadSize(rawText),
                  let classification = ClipClassifier.classify(rawText) else {
                return .ignoredInvalidOrTooLarge
            }

            let snapshot = state

            if let existingIndex = state.items.firstIndex(where: {
                $0.kind != .image && ($0.content == rawText || $0.content == classification.normalizedContent)
            }) {
                var existing = state.items.remove(at: existingIndex)
                existing.updatedAt = now
                state.items.insert(existing, at: 0)
                guard persistLocked() else {
                    state = snapshot
                    return .persistenceFailed
                }
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
                image: nil,
                createdAt: now,
                updatedAt: now
            )
            state.items.insert(newItem, at: 0)
            trimToMaxItemsLocked()
            guard persistLocked() else {
                state = snapshot
                return .persistenceFailed
            }
            imageAssets.removeOrphanedAssets(retaining: state.items)
            return .inserted(newItem)
        }
    }

    @discardableResult
    public func ingestImage(_ rawData: Data, now: Date = Date()) -> IngestResult {
        switch ImageAssetStore.prepareCanonicalPNG(from: rawData) {
        case .failure:
            return .ignoredInvalidOrTooLarge
        case .success(let prepared):
            lock.lock()
            defer { lock.unlock() }

            return withFileLock(exclusive: true) {
                reloadIfChangedLocked(force: true)

                guard !state.isPaused else {
                    return .ignoredPaused
                }

                let snapshot = state

                if let existingIndex = state.items.firstIndex(where: { $0.kind == .image && $0.image?.sha256 == prepared.sha256 }) {
                    do {
                        try imageAssets.saveAssetIfNeeded(prepared)
                    } catch {
                        return .persistenceFailed
                    }
                    var existing = state.items.remove(at: existingIndex)
                    existing.updatedAt = now
                    state.items.insert(existing, at: 0)
                    guard persistLocked() else {
                        state = snapshot
                        return .persistenceFailed
                    }
                    return .bumpedExisting(existing)
                }

                do {
                    try imageAssets.saveAssetIfNeeded(prepared)
                } catch {
                    return .persistenceFailed
                }

                let meta = prepared.metadata
                let seq = state.nextSequence
                state.nextSequence += 1
                let newItem = ClipItem(
                    id: SpeakableID.makeID(sequence: seq),
                    sequence: seq,
                    kind: .image,
                    content: "Image \(meta.dimensionsLabel) PNG · \(meta.formattedByteSize)",
                    domain: nil,
                    image: meta,
                    createdAt: now,
                    updatedAt: now
                )
                state.items.insert(newItem, at: 0)
                trimToMaxItemsLocked()
                guard persistLocked() else {
                    state = snapshot
                    imageAssets.removeOrphanedAssets(retaining: state.items)
                    return .persistenceFailed
                }
                imageAssets.removeOrphanedAssets(retaining: state.items)
                return .inserted(newItem)
            }
        }
    }

    /// Explicit user-directed text/URL write from CLI or MCP.
    public func writeFromAgent(_ rawText: String, now: Date = Date(), afterPersist: ((ClipItem) -> Void)? = nil) -> Result<AgentWriteOutcome, AgentWriteError> {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyContent)
        }
        guard PasteboardPrivacyFilter.isAllowedPayloadSize(rawText) else {
            return .failure(.payloadTooLarge(maxBytes: PasteboardPrivacyFilter.maxContentUTF8Bytes))
        }
        guard let classification = ClipClassifier.classify(rawText) else {
            return .failure(.emptyContent)
        }

        lock.lock()
        defer { lock.unlock() }

        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            let snapshot = state

            if let existingIndex = state.items.firstIndex(where: { $0.kind != .image && $0.content == rawText }) {
                var existing = state.items.remove(at: existingIndex)
                existing.updatedAt = now
                state.items.insert(existing, at: 0)
                guard persistLocked() else {
                    state = snapshot
                    return .failure(.persistenceFailed("Could not write history file."))
                }
                afterPersist?(existing)
                return .success(.bumpedExisting(existing))
            }

            let seq = state.nextSequence
            state.nextSequence += 1
            let newItem = ClipItem(
                id: SpeakableID.makeID(sequence: seq),
                sequence: seq,
                kind: classification.kind,
                content: rawText,
                domain: classification.domain,
                image: nil,
                createdAt: now,
                updatedAt: now
            )
            state.items.insert(newItem, at: 0)
            trimToMaxItemsLocked()
            guard persistLocked() else {
                state = snapshot
                return .failure(.persistenceFailed("Could not write history file."))
            }
            imageAssets.removeOrphanedAssets(retaining: state.items)
            afterPersist?(newItem)
            return .success(.inserted(newItem))
        }
    }

    /// Explicit user-directed image write from CLI or MCP.
    public func writeImageFromAgent(
        _ rawData: Data,
        now: Date = Date(),
        afterPersist: ((PreparedImageAsset, ClipItem) -> Void)? = nil
    ) -> Result<AgentWriteOutcome, AgentWriteError> {
        let prepared: PreparedImageAsset
        switch ImageAssetStore.prepareCanonicalPNG(from: rawData) {
        case .failure(let err):
            return .failure(.invalidImage(err.localizedDescription))
        case .success(let asset):
            prepared = asset
        }

        lock.lock()
        defer { lock.unlock() }

        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            let snapshot = state

            do {
                try imageAssets.saveAssetIfNeeded(prepared)
            } catch {
                return .failure(.persistenceFailed(error.localizedDescription))
            }

            if let existingIndex = state.items.firstIndex(where: { $0.kind == .image && $0.image?.sha256 == prepared.sha256 }) {
                var existing = state.items.remove(at: existingIndex)
                existing.updatedAt = now
                state.items.insert(existing, at: 0)
                guard persistLocked() else {
                    state = snapshot
                    imageAssets.removeOrphanedAssets(retaining: state.items)
                    return .failure(.persistenceFailed("Could not write history file."))
                }
                afterPersist?(prepared, existing)
                return .success(.bumpedExisting(existing))
            }

            let meta = prepared.metadata
            let seq = state.nextSequence
            state.nextSequence += 1
            let newItem = ClipItem(
                id: SpeakableID.makeID(sequence: seq),
                sequence: seq,
                kind: .image,
                content: "Image \(meta.dimensionsLabel) PNG · \(meta.formattedByteSize)",
                domain: nil,
                image: meta,
                createdAt: now,
                updatedAt: now
            )
            state.items.insert(newItem, at: 0)
            trimToMaxItemsLocked()
            guard persistLocked() else {
                state = snapshot
                imageAssets.removeOrphanedAssets(retaining: state.items)
                return .failure(.persistenceFailed("Could not write history file."))
            }
            imageAssets.removeOrphanedAssets(retaining: state.items)
            afterPersist?(prepared, newItem)
            return .success(.inserted(newItem))
        }
    }

    @discardableResult
    public func bumpToTop(id: String, now: Date = Date()) -> ClipItem? {
        lock.lock()
        defer { lock.unlock() }
        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            let snapshot = state
            guard let index = state.items.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            var item = state.items.remove(at: index)
            item.updatedAt = now
            state.items.insert(item, at: 0)
            guard persistLocked() else {
                state = snapshot
                return nil
            }
            return item
        }
    }

    @discardableResult
    public func delete(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            let snapshot = state
            let before = state.items.count
            state.items.removeAll { $0.id == id }
            let removed = state.items.count != before
            guard removed else {
                return false
            }
            guard persistLocked() else {
                state = snapshot
                return false
            }
            imageAssets.removeOrphanedAssets(retaining: state.items)
            return true
        }
    }

    @discardableResult
    public func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            let snapshot = state
            state.items.removeAll()
            guard persistLocked() else {
                state = snapshot
                return false
            }
            imageAssets.removeOrphanedAssets(retaining: state.items)
            return true
        }
    }

    @discardableResult
    public func setPaused(_ paused: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            guard state.isPaused != paused else { return true }
            let snapshot = state
            state.isPaused = paused
            guard persistLocked() else {
                state = snapshot
                return false
            }
            return true
        }
    }

    @discardableResult
    public func setMaxItems(_ maxItems: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return withFileLock(exclusive: true) {
            reloadIfChangedLocked(force: true)
            let snapshot = state
            state.maxItems = ClipStoreState.clampMaxItems(maxItems)
            trimToMaxItemsLocked()
            guard persistLocked() else {
                state = snapshot
                return false
            }
            imageAssets.removeOrphanedAssets(retaining: state.items)
            return true
        }
    }

    // MARK: - Cross-Process File Locking & Persistence Helpers

    private func withFileLock<T>(exclusive: Bool, _ body: () -> T) -> T {
        let fm = FileManager.default
        let parent = lockFileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [
            .posixPermissions: NSNumber(value: Int16(0o700))
        ])

        let fd = Darwin.open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            return body()
        }
        defer {
            _ = c_flock(fd, LOCK_UN)
            Darwin.close(fd)
        }
        _ = c_flock(fd, exclusive ? LOCK_EX : LOCK_SH)
        return body()
    }

    private func trimToMaxItemsLocked() {
        if state.items.count > state.maxItems {
            state.items = Array(state.items.prefix(state.maxItems))
        }
    }

    private func loadFromDiskIfPresent() throws {
        lock.lock()
        defer { lock.unlock() }
        withFileLock(exclusive: false) {
            reloadIfChangedLocked(force: true)
        }
    }

    private func reloadIfChangedLocked(force: Bool = false) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
            if force {
                state = ClipStoreState()
            }
            return
        }
        guard !isDir.boolValue else {
            return
        }

        let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
        let modDate = attrs?[.modificationDate] as? Date
        if !force, let modDate, let lastLoadedModifiedAt, modDate <= lastLoadedModifiedAt {
            return
        }

        for attempt in 0..<3 {
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? decoder.decode(ClipStoreState.self, from: data) {
                var sanitized = decoded
                sanitized.schemaVersion = max(decoded.schemaVersion, ClipVoiceVersion.schemaVersion)
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

    @discardableResult
    private func persistLocked() -> Bool {
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
            return true
        } catch {
            FileHandle.standardError.write(Data("ClipVoice store write error: \(error.localizedDescription)\n".utf8))
            return false
        }
    }
}
