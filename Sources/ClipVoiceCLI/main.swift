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
        case "--target":
            if i + 1 < args.count { opts.target = args[i + 1]; i += 2 } else { i += 1 }
        case "--skill-source":
            if i + 1 < args.count { opts.skillSource = args[i + 1]; i += 2 } else { i += 1 }
        case "--json":
            opts.json = true; i += 1
        case "--raw":
            opts.raw = true; i += 1
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
      clipvoice-cli list [--kind all|url|text] [--query TEXT] [--limit N] [--json] [--store PATH]
      clipvoice-cli get <id> [--raw] [--json] [--store PATH]
      clipvoice-cli search <query> [--kind all|url|text] [--limit N] [--json] [--store PATH]
      clipvoice-cli latest [--kind all|url|text] [--raw] [--json] [--store PATH]
      clipvoice-cli mcp [--store PATH]
      clipvoice-cli install-skill [--target codex|claude|agents|<dir>] [--backup] [--skill-source PATH]
      clipvoice-cli version

    EXAMPLES:
      clipvoice-cli list --kind url
      clipvoice-cli get clip-4 --raw
      clipvoice-cli get "clip four" --json
      clipvoice-cli install-skill --target codex
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
        let tag = item.kind == .url ? "[URL:\(item.domain ?? "link")]" : "[TEXT:\(item.charCount)c]"
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
    print("clipvoice \(ClipVoiceVersion.current)")
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
        FileHandle.standardError.write(Data("Error: missing clip id (e.g. clipvoice get clip-1)\n".utf8))
        exit(2)
    }
    guard let item = store.get(idOrSpoken: query) else {
        FileHandle.standardError.write(Data("Error: clip '\(query)' not found.\n".utf8))
        exit(1)
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

    // Enumerate only known files from the bundled skill directory.
    let knownRelativeFiles = ["SKILL.md"]
    let timestampFormatter = ISO8601DateFormatter()
    timestampFormatter.formatOptions = [.withInternetDateTime]
    let timestamp = timestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

    do {
        // Pre-flight conflict check before modifying any file on disk.
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
    FileHandle.standardError.write(Data("Unknown command '\(command)'. Run 'clipvoice --help'.\n".utf8))
    exit(2)
}
