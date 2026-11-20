import Foundation
import ClipVoiceCore

@MainActor
final class MCPActivityMonitor {
    private let storeID: String
    private let watermark: MCPActivityWatermark
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private let onActivity: (MCPActivityEvent) -> Void

    init(storeFileURL: URL, onActivity: @escaping (MCPActivityEvent) -> Void) {
        self.storeID = MCPActivitySignal.storeIdentifier(for: storeFileURL)
        self.watermark = MCPActivityWatermark(storeFileURL: storeFileURL)
        self.onActivity = onActivity
    }

    func start() {
        if observer == nil {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: MCPActivitySignal.notificationName,
                object: storeID,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkSignalFile()
                }
            }
        }

        if timer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkSignalFile()
                }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    func checkSignalFile() {
        if let event = watermark.poll() {
            onActivity(event)
        }
    }
}
