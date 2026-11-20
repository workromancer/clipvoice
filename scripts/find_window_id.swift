import Foundation
import CoreGraphics

guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("Usage: find_window_id.swift <pid>\n", stderr)
    exit(2)
}

let deadline = Date().addingTimeInterval(8.0)
while Date() < deadline {
    if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
        for info in list {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
               ownerPID == pid,
               let layer = info[kCGWindowLayer as String] as? Int,
               layer >= 0,
               let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? Double,
               let height = bounds["Height"] as? Double,
               width >= 350, height >= 350,
               let winID = info[kCGWindowNumber as String] as? UInt32 {
                print(winID)
                exit(0)
            }
        }
    }
    Thread.sleep(forTimeInterval: 0.2)
}

fputs("Could not find on-screen HUD window for pid \(pid)\n", stderr)
exit(1)
