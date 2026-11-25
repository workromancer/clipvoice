import AppKit
import Foundation

public enum SystemPasteboardWriter {
    @discardableResult
    public static func writePlainText(_ text: String, pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    public static func writeImagePNG(_ pngData: Data, pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let nsImage = NSImage(data: pngData), let tiff = nsImage.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    public static func copyClipItem(_ item: ClipItem, store: ClipStore, pasteboard: NSPasteboard = .general) -> Int? {
        if item.kind == .image {
            guard let meta = item.image,
                  let pngData = store.imageAssets.readPNGData(for: meta) else {
                return nil
            }
            return writeImagePNG(pngData, pasteboard: pasteboard)
        }
        return writePlainText(item.content, pasteboard: pasteboard)
    }

    public static func performAgentWrite(
        text: String,
        store: ClipStore,
        operation: MCPActivityOperation,
        pasteboard: NSPasteboard = .general
    ) -> Result<AgentWriteOutcome, AgentWriteError> {
        var capturedChangeCount: Int?
        let result = store.writeFromAgent(text) { _ in
            capturedChangeCount = writePlainText(text, pasteboard: pasteboard)
        }
        if case .success(let outcome) = result {
            MCPActivitySignal.emit(
                operation: operation,
                storeFileURL: store.fileURL,
                targetItemID: outcome.item.id,
                pasteboardChangeCount: capturedChangeCount
            )
        }
        return result
    }

    public static func performAgentImageWrite(
        filePath: String,
        store: ClipStore,
        operation: MCPActivityOperation,
        pasteboard: NSPasteboard = .general
    ) -> Result<AgentWriteOutcome, AgentWriteError> {
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidImage("Missing local file path."))
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return .failure(.invalidImage("Remote URLs are not permitted; provide a local image file path."))
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(.invalidImage("File does not exist or is a directory: \(url.path)"))
        }

        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = (attrs[.size] as? NSNumber)?.intValue,
           size > ImageAssetStore.maxCompressedInputBytes {
            return .failure(.invalidImage("File exceeds \(ImageAssetStore.maxCompressedInputBytes) byte limit."))
        }

        guard let rawData = try? Data(contentsOf: url) else {
            return .failure(.invalidImage("Could not read file at \(url.path)"))
        }

        var capturedChangeCount: Int?
        let result = store.writeImageFromAgent(rawData) { prepared, _ in
            capturedChangeCount = writeImagePNG(prepared.pngData, pasteboard: pasteboard)
        }
        if case .success(let outcome) = result {
            MCPActivitySignal.emit(
                operation: operation,
                storeFileURL: store.fileURL,
                targetItemID: outcome.item.id,
                pasteboardChangeCount: capturedChangeCount
            )
        }
        return result
    }
}
