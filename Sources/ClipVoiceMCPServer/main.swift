import Foundation
import ClipVoiceCore
import ClipVoiceMCP

var storeArg: String?
let args = Array(CommandLine.arguments.dropFirst())
var idx = 0
while idx < args.count {
    let arg = args[idx]
    if arg == "--store", idx + 1 < args.count {
        storeArg = args[idx + 1]
        idx += 2
    } else if arg == "--version" || arg == "-v" {
        print("clipvoice-mcp \(ClipVoiceVersion.current)")
        exit(0)
    } else if arg == "--help" || arg == "-h" {
        print("""
        clipvoice-mcp \(ClipVoiceVersion.current)
        Local stdio MCP server exposing ClipVoice clipboard entries.

        USAGE:
          clipvoice-mcp [--store <path>]
        """)
        exit(0)
    } else {
        idx += 1
    }
}

let storeURL = StorePathResolver.resolve(cliArgument: storeArg)
let store = ClipStore(fileURL: storeURL)
let server = ClipVoiceMCPServerHandler(store: store)
server.runStdioLoop()
