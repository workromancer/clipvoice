import Foundation
import AppKit
import ClipVoiceCore

@MainActor
final class ClipboardMonitor {
    private let store: ClipStore
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int
    private var onStoreChanged: () -> Void

    init(store: ClipStore, pasteboard: NSPasteboard = .general, onStoreChanged: @escaping () -> Void) {
        self.store = store
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.onStoreChanged = onStoreChanged
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func writeToPasteboardAndSuppressReingest(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func pollPasteboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let extracted = PasteboardPrivacyFilter.extractPlainText(from: pasteboard) else {
            return
        }

        let result = store.ingest(extracted)
        switch result {
        case .inserted, .bumpedExisting:
            onStoreChanged()
        case .ignoredPaused, .ignoredInvalidOrTooLarge:
            break
        }
    }
}
