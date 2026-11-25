import Foundation
import ClipVoiceCore
import ClipVoiceMCP

struct CLIOptions {
    var storePath: String?
    var kind: ClipKind?
    var query: String?
    var limit: Int?
    var json: Bool = false
    var raw: Bool = false
    var useStdin: Bool = false
    var filePath: String?
    var outputFile: String?
    var backup: Bool = false
    var target: String = "codex"
    var skillSource: String?
    var positional: [String] = []
}

func parseOptions(_ args: [String]) -> CLIOptions {
    var opts = CLIOptions()
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--store":
            if i + 1 < args.count { opts.storePath = args[i + 1]; i += 2 } else { i += 1 }
        case "--kind":
            if i + 1 < args.count {
                let val = args[i + 1].lowercased()
                opts.kind = val == "all" ? nil : ClipKind(rawValue: val)
                i += 2
            } else { i += 1 }
        case "--query":
            if i + 1 < args.count { opts.query = args[i + 1]; i += 2 } else { i += 1 }
        case "--limit":
            if i + 1 < args.count { opts.limit = Int(args[i + 1]); i += 2 } else { i += 1 }
        case "--file":
            if i + 1 < args.count { opts.filePath = args[i + 1]; i += 2 } else { i += 1 }
        case "--output-file":
            if i + 1 < args.count { opts.outputFile = args[i + 1]; i += 2 } else { i += 1 }
        case "--target":
            if i + 1 < args.count { opts.target = args[i + 1]; i += 2 } else { i += 1 }
        case "--skill-source":
            if i + 1 < args.count { opts.skillSource = args[i + 1]; i += 2 } else { i += 1 }
        case "--json":
            opts.json = true; i += 1
        case "--raw":
            opts.raw = true; i += 1
        case "--stdin":
            opts.useStdin = true; i += 1
        case "--backup":
            opts.backup = true; i += 1
        default:
            opts.positional.append(arg); i += 1
        }
    }
    return opts
}

func printHelp() {
    print("""
    clipvoice-cli \(ClipVoiceVersion.current) — Local CLI & MCP bridge for ClipVoice

    USAGE:
      clipvoice-cli list [--kind all|url|text|image] [--query TEXT] [--limit N] [--json] [--store PATH]
      clipvoice-cli get <id> [--raw | --output-file PATH] [--json] [--store PATH]
      clipvoice-cli search <query> [--kind all|url|text|image] [--limit N] [--json] [--store PATH]
      clipvoice-cli latest [--kind all|url|text|image] [--raw | --output-file PATH] [--json] [--store PATH]
      clipvoice-cli write (--stdin | --file PATH) [--json] [--store PATH]
      clipvoice-cli write-image --file PATH [--json] [--store PATH]
      clipvoice-cli mcp [--store PATH]
      clipvoice-cli install-skill [--target codex|claude|agents|<dir>] [--backup] [--skill-source PATH]
      clipvoice-cli version

    EXAMPLES:
      clipvoice-cli list --kind image --json
      clipvoice-cli get clip-4 --raw
      clipvoice-cli get clip-5 --output-file /tmp/clip-5.png --json
      printf '%s' 'https://example.com' | clipvoice-cli write --stdin --json
      clipvoice-cli write-image --file ./diagram.png --json
    """)
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func printItemTable(_ items: [ClipItem]) {
    if items.isEmpty {
        print("No clipboard items found.")
        return
    }
    for item in items {
        let tag: String
        switch item.kind {
        case .url:
            tag = "[URL:\(item.domain ?? "link")]"
        case .text:
            tag = "[TEXT:\(item.charCount)c]"
        case .image:
            tag = "[IMAGE:\(item.image?.dimensionsLabel ?? "png")]"
        }
        print("\(item.id)\t\(tag)\t\(item.preview)")
    }
}

func resolveSkillDestination(target: String) -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    switch target.lowercased() {
    case "codex":
        return home.appendingPathComponent(".codex/skills/clipvoice", isDirectory: true)
    case "claude":
        return home.appendingPathComponent(".claude/skills/clipvoice", isDirectory: true)
    case "agents":
        return home.appendingPathComponent(".agents/skills/clipvoice", isDirectory: true)
    default:
        let expanded = (target as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

func findBundledSkillSource(explicit: String?) -> URL? {
    let fm = FileManager.default
    if let explicit {
        let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath, isDirectory: true)
        if fm.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) {
            return url
        }
    }

    let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidates = [
        execURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/skills/clipvoice", isDirectory: true),
        URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true).appendingPathComponent("skills/clipvoice", isDirectory: true),
        URL(fileURLWithPath: "/Applications/ClipVoice.app/Contents/Resources/skills/clipvoice", isDirectory: true)
    ]
    return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
}

struct WriteCommandOutput: Encodable {
    let id: String
    let sequence: Int
    let kind: String
    let domain: String?
    let image: ClipImageMetadata?
    let status: String
    let charCount: Int
    let lineCount: Int
}

struct ImageExportOutput: Encodable {
    let id: String
    let kind: String
    let outputFile: String
    let width: Int
    let height: Int
    let byteSize: Int
    let mimeType: String
    let sha256: String
}

func handleItemFetchOutput(item: ClipItem, opts: CLIOptions, store: ClipStore) {
    if item.kind == .image {
        if opts.raw {
            FileHandle.standardError.write(Data("Error: '\(item.id)' is an image clip; pass --output-file <path> instead of --raw to avoid dumping binary PNG bytes to stdout.\n".utf8))
            exit(2)
        }
        guard let meta = item.image else {
            FileHandle.standardError.write(Data("Error: image metadata missing for '\(item.id)'.\n".utf8))
            exit(1)
        }
        if let outPath = opts.outputFile {
            guard let pngData = store.imageAssets.readPNGData(for: meta) else {
                FileHandle.standardError.write(Data("Error: image asset missing or unreadable for '\(item.id)'.\n".utf8))
                exit(1)
            }
            let expanded = (outPath as NSString).expandingTildeInPath
            let destURL = URL(fileURLWithPath: expanded)
            do {
                try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pngData.write(to: destURL, options: [.atomic])
            } catch {
                FileHandle.standardError.write(Data("Error writing image to '\(destURL.path)': \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            if opts.json {
                printJSON(ImageExportOutput(
                    id: item.id,
                    kind: item.kind.rawValue,
                    outputFile: destURL.path,
                    width: meta.width,
                    height: meta.height,
                    byteSize: meta.byteSize,
                    mimeType: meta.mimeType,
                    sha256: meta.sha256
                ))
            } else {
                print("Exported \(item.id) (\(meta.dimensionsLabel) PNG, \(meta.byteSize) bytes) to \(destURL.path)")
            }
            return
        }
        if opts.json {
            printJSON(item)
        } else {
            print("ID: \(item.id)")
            print("Kind: \(item.kind.rawValue)")
            print("Dimensions: \(meta.dimensionsLabel)")
            print("Bytes: \(meta.byteSize)")
            print("SHA256: \(meta.sha256)")
            if let path = store.imageAssets.resolveAssetURL(for: meta)?.path {
                print("ManagedAsset: \(path)")
            }
        }
        return
    }

    if let outPath = opts.outputFile {
        let expanded = (outPath as NSString).expandingTildeInPath
        do {
            try Data(item.content.utf8).write(to: URL(fileURLWithPath: expanded), options: [.atomic])
        } catch {
            FileHandle.standardError.write(Data("Error writing output file: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    if opts.raw {
        FileHandle.standardOutput.write(Data(item.content.utf8))
    } else if opts.json {
        printJSON(item)
    } else {
        print("ID: \(item.id)")
        print("Kind: \(item.kind.rawValue)")
        if let domain = item.domain { print("Domain: \(domain)") }
        print("Content:\n\(item.content)")
    }
}

let allArgs = Array(CommandLine.arguments.dropFirst())
guard let command = allArgs.first else {
    printHelp()
    exit(0)
}

if command == "--help" || command == "-h" || command == "help" {
    printHelp()
    exit(0)
}
if command == "--version" || command == "-v" || command == "version" {
    print("clipvoice-cli \(ClipVoiceVersion.current)")
    exit(0)
}

let opts = parseOptions(Array(allArgs.dropFirst()))
let store = ClipStore(fileURL: StorePathResolver.resolve(cliArgument: opts.storePath))

switch command {
case "list":
    let items = store.list(kind: opts.kind, query: opts.query, limit: opts.limit)
    if opts.json {
        printJSON(items)
    } else {
        printItemTable(items)
    }

case "get":
    let query = opts.positional.joined(separator: " ")
    guard !query.isEmpty else {
        FileHandle.standardError.write(Data("Error: missing clip id (e.g. clipvoice-cli get clip-1)\n".utf8))
        exit(2)
    }
    guard let item = store.get(idOrSpoken: query) else {
        FileHandle.standardError.write(Data("Error: clip '\(query)' not found.\n".utf8))
        exit(1)
    }
    handleItemFetchOutput(item: item, opts: opts, store: store)

case "search":
    let query = opts.positional.joined(separator: " ")
    guard !query.isEmpty else {
        FileHandle.standardError.write(Data("Error: missing search query.\n".utf8))
        exit(2)
    }
    let items = store.list(kind: opts.kind, query: query, limit: opts.limit)
    if opts.json {
        printJSON(items)
    } else {
        printItemTable(items)
    }

case "latest":
    guard let item = store.latest(kind: opts.kind) else {
        FileHandle.standardError.write(Data("Error: no matching clips found.\n".utf8))
        exit(1)
    }
    handleItemFetchOutput(item: item, opts: opts, store: store)

case "write":
    if !opts.positional.isEmpty {
        FileHandle.standardError.write(Data("Error: 'write' does not accept positional text arguments; pass --stdin or --file <path>.\n".utf8))
        exit(2)
    }
    guard opts.useStdin != (opts.filePath != nil) else {
        FileHandle.standardError.write(Data("Error: specify exactly one of --stdin or --file <path>.\n".utf8))
        exit(2)
    }

    let rawData: Data
    if opts.useStdin {
        rawData = (try? FileHandle.standardInput.readToEnd()) ?? Data()
    } else if let filePath = opts.filePath {
        let expanded = (filePath as NSString).expandingTildeInPath
        do {
            rawData = try Data(contentsOf: URL(fileURLWithPath: expanded))
        } catch {
            FileHandle.standardError.write(Data("Error reading file '\(filePath)': \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    } else {
        rawData = Data()
    }

    guard let text = String(data: rawData, encoding: .utf8) else {
        FileHandle.standardError.write(Data("Error: input is not valid UTF-8 text.\n".utf8))
        exit(1)
    }

    let result = SystemPasteboardWriter.performAgentWrite(
        text: text,
        store: store,
        operation: .agentWrite
    )
    switch result {
    case .success(let outcome):
        let item = outcome.item
        let status = outcome.isNew ? "created" : "updated"
        if opts.json {
            printJSON(WriteCommandOutput(
                id: item.id,
                sequence: item.sequence,
                kind: item.kind.rawValue,
                domain: item.domain,
                image: item.image,
                status: status,
                charCount: item.charCount,
                lineCount: item.lineCount
            ))
        } else {
            print("Wrote \(item.id) (\(status)) to clipboard")
        }
    case .failure(let error):
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "write-image":
    if !opts.positional.isEmpty {
        FileHandle.standardError.write(Data("Error: 'write-image' requires --file <path>.\n".utf8))
        exit(2)
    }
    guard let filePath = opts.filePath, !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        FileHandle.standardError.write(Data("Error: missing required --file <path> argument.\n".utf8))
        exit(2)
    }

    let result = SystemPasteboardWriter.performAgentImageWrite(
        filePath: filePath,
        store: store,
        operation: .agentWrite
    )
    switch result {
    case .success(let outcome):
        let item = outcome.item
        let status = outcome.isNew ? "created" : "updated"
        if opts.json {
            printJSON(WriteCommandOutput(
                id: item.id,
                sequence: item.sequence,
                kind: item.kind.rawValue,
                domain: item.domain,
                image: item.image,
                status: status,
                charCount: item.charCount,
                lineCount: item.lineCount
            ))
        } else {
            print("Wrote image \(item.id) (\(status), \(item.image?.dimensionsLabel ?? "png")) to clipboard")
        }
    case .failure(let error):
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "mcp":
    let server = ClipVoiceMCPServerHandler(store: store)
    server.runStdioLoop()

case "install-skill":
    guard let src = findBundledSkillSource(explicit: opts.skillSource) else {
        FileHandle.standardError.write(Data("Error: could not locate skills/clipvoice/SKILL.md.\n".utf8))
        exit(1)
    }
    let dest = resolveSkillDestination(target: opts.target)
    let fm = FileManager.default

    var isDir: ObjCBool = false
    if fm.fileExists(atPath: dest.path, isDirectory: &isDir), !isDir.boolValue {
        FileHandle.standardError.write(Data("Error: destination '\(dest.path)' exists and is not a directory.\n".utf8))
        exit(1)
    }

    let knownRelativeFiles = ["SKILL.md"]
    let timestampFormatter = ISO8601DateFormatter()
    timestampFormatter.formatOptions = [.withInternetDateTime]
    let timestamp = timestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

    do {
        var conflicts: [(src: URL, dest: URL, identical: Bool)] = []
        for rel in knownRelativeFiles {
            let srcFile = src.appendingPathComponent(rel)
            let destFile = dest.appendingPathComponent(rel)
            if fm.fileExists(atPath: destFile.path) {
                var destFileIsDir: ObjCBool = false
                _ = fm.fileExists(atPath: destFile.path, isDirectory: &destFileIsDir)
                if destFileIsDir.boolValue {
                    FileHandle.standardError.write(Data("Error: conflicting directory at '\(destFile.path)'.\n".utf8))
                    exit(1)
                }
                let existingData = try Data(contentsOf: destFile)
                let newData = try Data(contentsOf: srcFile)
                let identical = existingData == newData
                conflicts.append((srcFile, destFile, identical))
                if !identical && !opts.backup {
                    FileHandle.standardError.write(Data("Error: conflicting file already exists at '\(destFile.path)'. Refusing to overwrite; pass --backup to back up existing file or choose an empty target directory.\n".utf8))
                    exit(1)
                }
            }
        }

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        for rel in knownRelativeFiles {
            let srcFile = src.appendingPathComponent(rel)
            let destFile = dest.appendingPathComponent(rel)
            try fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fm.fileExists(atPath: destFile.path) {
                if let match = conflicts.first(where: { $0.dest == destFile }), match.identical {
                    continue
                }
                let backupURL = URL(fileURLWithPath: destFile.path + ".bak.\(timestamp)")
                try fm.moveItem(at: destFile, to: backupURL)
                print("Backed up existing \(rel) to \(backupURL.path)")
            }
            try fm.copyItem(at: srcFile, to: destFile)
        }

        print("Installed ClipVoice skill to \(dest.path)")
    } catch {
        FileHandle.standardError.write(Data("Error installing skill: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

default:
    FileHandle.standardError.write(Data("Unknown command '\(command)'. Run 'clipvoice-cli --help'.\n".utf8))
    exit(2)
}
