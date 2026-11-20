import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: pb_snapshot.swift <save|restore> <archive-path>\n", stderr)
    exit(2)
}

let action = CommandLine.arguments[1]
let archiveURL = URL(fileURLWithPath: CommandLine.arguments[2])
let pb = NSPasteboard.general

switch action {
case "save":
    var serializedItems: [[[String: Any]]] = []
    if let items = pb.pasteboardItems {
        for item in items {
            var entries: [[String: Any]] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    entries.append([
                        "type": type.rawValue,
                        "data": data
                    ])
                }
            }
            serializedItems.append(entries)
        }
    }
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: serializedItems,
        format: .binary,
        options: 0
    )
    try plistData.write(to: archiveURL, options: .atomic)
    try? FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o600))],
        ofItemAtPath: archiveURL.path
    )

case "restore":
    guard FileManager.default.fileExists(atPath: archiveURL.path) else {
        exit(0)
    }
    let plistData = try Data(contentsOf: archiveURL)
    guard let serializedItems = try PropertyListSerialization.propertyList(
        from: plistData,
        options: [],
        format: nil
    ) as? [[[String: Any]]] else {
        exit(1)
    }

    pb.clearContents()
    if !serializedItems.isEmpty {
        var restored: [NSPasteboardItem] = []
        for entries in serializedItems {
            let item = NSPasteboardItem()
            for entry in entries {
                if let typeStr = entry["type"] as? String,
                   let data = entry["data"] as? Data {
                    item.setData(data, forType: NSPasteboard.PasteboardType(typeStr))
                }
            }
            restored.append(item)
        }
        pb.writeObjects(restored)
    }

default:
    fputs("Unknown action: \(action)\n", stderr)
    exit(2)
}
