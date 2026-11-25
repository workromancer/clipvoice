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
        lastChangeCount = SystemPasteboardWriter.writePlainText(text, pasteboard: pasteboard)
    }

    @discardableResult
    func writeItemToPasteboardAndSuppressReingest(_ item: ClipItem) -> Bool {
        guard let newCount = SystemPasteboardWriter.copyClipItem(item, store: store, pasteboard: pasteboard) else {
            return false
        }
        lastChangeCount = newCount
        return true
    }

    func suppressChangeCount(_ changeCount: Int?) {
        guard let changeCount else { return }
        if changeCount >= lastChangeCount {
            lastChangeCount = changeCount
        }
    }

    func pollPasteboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let payload = PasteboardPrivacyFilter.extractPayload(from: pasteboard) else {
            return
        }

        let result: IngestResult
        switch payload {
        case .image(let data):
            result = store.ingestImage(data)
        case .text(let text):
            result = store.ingest(text)
        }

        switch result {
        case .inserted, .bumpedExisting:
            onStoreChanged()
        case .ignoredPaused, .ignoredInvalidOrTooLarge, .persistenceFailed:
            break
        }
    }
}
