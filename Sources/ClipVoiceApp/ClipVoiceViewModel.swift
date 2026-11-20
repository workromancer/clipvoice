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
    @Published var isPinned: Bool = true
    @Published var hotkeyEnabled: Bool = true
    @Published var showSetupSheet: Bool = false
    @Published var showClearConfirmation: Bool = false
    @Published var copiedFeedbackID: String?
    @Published private(set) var mcpActivityActive: Bool = false
    @Published private(set) var mcpActivityOperation: MCPActivityOperation?
    @Published private(set) var mcpActivityRevision: Int = 0

    let store: ClipStore
    var onCopyToPasteboard: ((String) -> Void)?
    var onTogglePin: ((Bool) -> Void)?
    var onToggleHotkey: ((Bool) -> Void)?
    var onHideHUD: (() -> Void)?
    var onStateChanged: (() -> Void)?

    private var feedbackResetTask: Task<Void, Never>?
    private var mcpExpiryTask: Task<Void, Never>?
    private let mcpPulseDurationNanoseconds: UInt64 = 5_000_000_000

    init(store: ClipStore, hotkeyEnabled: Bool = true) {
        self.store = store
        self.hotkeyEnabled = hotkeyEnabled
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
        allItems.count - urlCount
    }

    var selectedItem: ClipItem? {
        if let selectedItemID,
           let match = filteredItems.first(where: { $0.id == selectedItemID }) {
            return match
        }
        return filteredItems.first
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
        onCopyToPasteboard?(item.content)
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
        onTogglePin?(isPinned)
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
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

    var mcpActivityLabel: String? {
        guard mcpActivityActive else { return nil }
        if let op = mcpActivityOperation {
            return "\(L10n.tr("mcp.activity.active")) · \(L10n.tr(op.localizationKey))"
        }
        return L10n.tr("mcp.activity.active")
    }

    func recordMCPActivity(_ event: MCPActivityEvent) {
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
