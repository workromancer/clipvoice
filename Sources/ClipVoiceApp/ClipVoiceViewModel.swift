import Foundation
import AppKit
import Combine
import ClipVoiceCore

@MainActor
final class ClipVoiceViewModel: ObservableObject {
    @Published private(set) var allItems: [ClipItem] = []
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var maxItems: Int = 50
    @Published var selectedFilter: ClipFilter = .all
    @Published var searchText: String = ""
    @Published var selectedItemID: String?
    @Published var isPinned: Bool
    @Published var hotkeyEnabled: Bool
    @Published var placementMode: WindowPlacementMode
    @Published var opacity: Double
    @Published var showDisplayPopover: Bool = false
    @Published var showDetailPopover: Bool = false
    @Published var showSetupSheet: Bool = false
    @Published var showClearConfirmation: Bool = false
    @Published var copiedFeedbackID: String?

    // Subtle ~5s MCP activity state
    @Published private(set) var mcpActivityActive: Bool = false
    @Published private(set) var mcpActivityOperation: MCPActivityOperation?
    @Published private(set) var mcpActivityRevision: Int = 0

    // Subtle ~2s incoming agent-write entrance & highlight state
    @Published private(set) var incomingHighlightID: String?
    @Published private(set) var incomingIsNew: Bool = true
    @Published private(set) var incomingRevision: Int = 0
    @Published private(set) var incomingEntrancePending: Bool = false

    let store: ClipStore
    let preferences: AppPreferencesStore
    var onCopyToPasteboard: ((String) -> Void)?
    var onCopyItemToPasteboard: ((ClipItem) -> Bool)?
    var onSuppressPasteboardChangeCount: ((Int?) -> Void)?
    var onTogglePin: ((Bool) -> Void)?
    var onToggleHotkey: ((Bool) -> Void)?
    var onApplyPlacement: ((WindowPlacementMode) -> Void)?
    var onApplyOpacity: ((Double) -> Void)?
    var onResetDisplay: (() -> Void)?
    var onHideHUD: (() -> Void)?
    var onStateChanged: (() -> Void)?

    private var feedbackResetTask: Task<Void, Never>?
    private var mcpExpiryTask: Task<Void, Never>?
    private var incomingExpiryTask: Task<Void, Never>?
    private var incomingEntranceTask: Task<Void, Never>?
    private let mcpPulseDurationNanoseconds: UInt64 = 5_000_000_000
    private let incomingHighlightDurationNanoseconds: UInt64 = 2_000_000_000

    init(store: ClipStore, preferences: AppPreferencesStore, hotkeyEnabled: Bool? = nil) {
        self.store = store
        self.preferences = preferences
        self.isPinned = preferences.isPinned
        self.hotkeyEnabled = hotkeyEnabled ?? preferences.hotkeyEnabled
        self.placementMode = preferences.placementMode
        self.opacity = preferences.opacity
        refreshFromStore()
    }

    var filteredItems: [ClipItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allItems.filter { item in
            if let kind = selectedFilter.clipKind, item.kind != kind {
                return false
            }
            if !query.isEmpty {
                let matchesID = item.id.lowercased().contains(query)
                let matchesDomain = item.domain?.lowercased().contains(query) ?? false
                let matchesContent = item.content.lowercased().contains(query)
                return matchesID || matchesDomain || matchesContent
            }
            return true
        }
    }

    var urlCount: Int {
        allItems.reduce(into: 0) { count, item in
            if item.kind == .url { count += 1 }
        }
    }

    var textCount: Int {
        allItems.reduce(into: 0) { count, item in
            if item.kind == .text { count += 1 }
        }
    }

    var imageCount: Int {
        allItems.reduce(into: 0) { count, item in
            if item.kind == .image { count += 1 }
        }
    }

    var selectedItem: ClipItem? {
        if let selectedItemID,
           let match = filteredItems.first(where: { $0.id == selectedItemID }) {
            return match
        }
        return filteredItems.first
    }

    var mcpActivityLabel: String? {
        guard mcpActivityActive else { return nil }
        if let op = mcpActivityOperation {
            return "\(L10n.tr("mcp.activity.active")) · \(L10n.tr(op.localizationKey))"
        }
        return L10n.tr("mcp.activity.active")
    }

    func refreshFromStore() {
        store.reloadIfChangedOnDisk()
        let snapshot = store.currentState()
        allItems = snapshot.items
        isPaused = snapshot.isPaused
        maxItems = snapshot.maxItems
        if let selectedItemID, !allItems.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = allItems.first?.id
        } else if self.selectedItemID == nil {
            self.selectedItemID = allItems.first?.id
        }
        onStateChanged?()
    }

    func togglePause() {
        store.setPaused(!isPaused)
        refreshFromStore()
    }

    func copyItem(_ item: ClipItem) {
        if let onCopyItemToPasteboard {
            guard onCopyItemToPasteboard(item) else { return }
        } else {
            onCopyToPasteboard?(item.content)
        }
        store.bumpToTop(id: item.id)
        selectedItemID = item.id
        refreshFromStore()
        showCopiedFeedback(for: item.id)
    }

    func copyID(_ item: ClipItem) {
        onCopyToPasteboard?(item.id)
        showCopiedFeedback(for: item.id)
    }

    func copyVoicePrompt(_ item: ClipItem) {
        let prompt = "Fetch \(item.id) from ClipVoice"
        onCopyToPasteboard?(prompt)
        showCopiedFeedback(for: item.id)
    }

    func copyText(_ text: String, feedbackKey: String = "setup") {
        onCopyToPasteboard?(text)
        showCopiedFeedback(for: feedbackKey)
    }

    func deleteItem(_ item: ClipItem) {
        store.delete(id: item.id)
        refreshFromStore()
    }

    func clearAll() {
        store.clear()
        refreshFromStore()
    }

    func setMaxItems(_ value: Int) {
        store.setMaxItems(value)
        refreshFromStore()
    }

    func togglePin() {
        isPinned.toggle()
        preferences.isPinned = isPinned
        onTogglePin?(isPinned)
    }

    func setPinned(_ pinned: Bool) {
        guard isPinned != pinned else { return }
        isPinned = pinned
        preferences.isPinned = pinned
        onTogglePin?(pinned)
    }

    func setPlacementMode(_ mode: WindowPlacementMode) {
        placementMode = mode
        preferences.placementMode = mode
        onApplyPlacement?(mode)
    }

    func setOpacity(_ value: Double) {
        let clamped = AppPreferencesStore.clampOpacity(value)
        opacity = clamped
        preferences.opacity = clamped
        onApplyOpacity?(clamped)
    }

    func resetDisplayDefaults() {
        preferences.resetDisplayDefaults()
        placementMode = preferences.placementMode
        opacity = preferences.opacity
        isPinned = preferences.isPinned
        onTogglePin?(isPinned)
        onApplyOpacity?(opacity)
        onResetDisplay?()
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
        preferences.hotkeyEnabled = enabled
        onToggleHotkey?(enabled)
    }

    func selectNext() {
        let list = filteredItems
        guard !list.isEmpty else { return }
        guard let currentID = selectedItem?.id,
              let idx = list.firstIndex(where: { $0.id == currentID }) else {
            selectedItemID = list.first?.id
            return
        }
        let next = min(idx + 1, list.count - 1)
        selectedItemID = list[next].id
    }

    func selectPrevious() {
        let list = filteredItems
        guard !list.isEmpty else { return }
        guard let currentID = selectedItem?.id,
              let idx = list.firstIndex(where: { $0.id == currentID }) else {
            selectedItemID = list.first?.id
            return
        }
        let prev = max(idx - 1, 0)
        selectedItemID = list[prev].id
    }

    func copySelected() {
        guard let item = selectedItem else { return }
        copyItem(item)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        deleteItem(item)
    }

    func hideHUD() {
        onHideHUD?()
    }

    func handleActivityEvent(_ event: MCPActivityEvent) {
        if let changeCount = event.pasteboardChangeCount {
            onSuppressPasteboardChangeCount?(changeCount)
        }

        if event.operation.isIncomingWrite {
            let previousIDs = Set(allItems.map(\.id))
            refreshFromStore()
            if let targetID = event.targetItemID ?? allItems.first?.id {
                if !filteredItems.contains(where: { $0.id == targetID }) {
                    searchText = ""
                    selectedFilter = .all
                }
                selectedItemID = targetID
                incomingIsNew = !previousIDs.contains(targetID)
                triggerIncomingHighlight(for: targetID)
            }
        }

        if event.operation.isMCPAccess {
            mcpActivityOperation = event.operation
            mcpActivityRevision += 1
            mcpActivityActive = true

            mcpExpiryTask?.cancel()
            let duration = mcpPulseDurationNanoseconds
            mcpExpiryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: duration)
                guard !Task.isCancelled else { return }
                self?.mcpActivityActive = false
                self?.mcpActivityOperation = nil
            }
        }
    }

    private func triggerIncomingHighlight(for itemID: String) {
        incomingHighlightID = itemID
        incomingRevision += 1

        // Render one distinct initial frame (-10pt offset, dimmed opacity) before animating to final position.
        incomingEntranceTask?.cancel()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            incomingEntrancePending = false
        } else {
            incomingEntrancePending = true
            incomingEntranceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 24_000_000)
                guard !Task.isCancelled else { return }
                self?.incomingEntrancePending = false
            }
        }

        incomingExpiryTask?.cancel()
        let duration = incomingHighlightDurationNanoseconds
        incomingExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            if self?.incomingHighlightID == itemID {
                self?.incomingHighlightID = nil
            }
        }
    }

    private func showCopiedFeedback(for id: String) {
        copiedFeedbackID = id
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            if self?.copiedFeedbackID == id {
                self?.copiedFeedbackID = nil
            }
        }
    }
}
