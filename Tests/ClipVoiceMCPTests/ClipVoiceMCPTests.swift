import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ClipVoiceCore
@testable import ClipVoiceMCP

final class ClipVoiceMCPTests: XCTestCase {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipvoice-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("history.json", isDirectory: false)
    }

    private func decodeResponse(_ line: String?) throws -> [String: Any] {
        let raw = try XCTUnwrap(line)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMCPHandshakeToolsAndResources() throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipStore(fileURL: url)
        store.ingest("https://linear.app/team/issue/CV-101")
        store.ingest("func greet() { print(\"hello\") }")

        let server = ClipVoiceMCPServerHandler(store: store)

        // 1. initialize
        let initResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#))
        XCTAssertEqual(initResp["id"] as? Int, 1)
        let initResult = try XCTUnwrap(initResp["result"] as? [String: Any])
        XCTAssertEqual(initResult["protocolVersion"] as? String, "2024-11-05")
        let serverInfo = try XCTUnwrap(initResult["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "clipvoice-mcp")

        // 2. notification returns nil
        XCTAssertNil(server.handleLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))

        // 3. ping
        let pingResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":"ping-1","method":"ping"}"#))
        XCTAssertEqual(pingResp["id"] as? String, "ping-1")
        XCTAssertNotNil(pingResp["result"])

        // 4. tools/list
        let listToolsResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let toolsResult = try XCTUnwrap(listToolsResp["result"] as? [String: Any])
        let tools = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]])
        let toolNames = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(toolNames, ["list_clips", "get_clip", "search_clips", "get_latest_clip", "write_clip", "write_image"])

        // 5. list_clips filtered by kind=url
        let listClipsResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_clips","arguments":{"kind":"url"}}}"#))
        let listResult = try XCTUnwrap(listClipsResp["result"] as? [String: Any])
        XCTAssertEqual(listResult["isError"] as? Bool, false)
        let listContent = try XCTUnwrap((listResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(listContent.contains("clip-1"))
        XCTAssertTrue(listContent.contains("linear.app"))
        XCTAssertFalse(listContent.contains("clip-2"))

        // 6. get_clip using spoken variant "clip two"
        let getClipResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip two"}}}"#))
        let getResult = try XCTUnwrap(getClipResp["result"] as? [String: Any])
        XCTAssertEqual(getResult["isError"] as? Bool, false)
        let getText = try XCTUnwrap((getResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(getText.contains("clip-2"))
        XCTAssertTrue(getText.contains("func greet()"))

        // 7. get_latest_clip
        let latestResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_latest_clip","arguments":{"kind":"url"}}}"#))
        let latestResult = try XCTUnwrap(latestResp["result"] as? [String: Any])
        let latestText = try XCTUnwrap((latestResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(latestText.contains("https://linear.app/team/issue/CV-101"))

        // 8. unknown clip returns isError=true with helpful recent IDs
        let missingResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip-999"}}}"#))
        let missingResult = try XCTUnwrap(missingResp["result"] as? [String: Any])
        XCTAssertEqual(missingResult["isError"] as? Bool, true)
        let missingText = try XCTUnwrap((missingResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(missingText.contains("clip-2"))

        // 9. resources/list & resources/read
        let resListResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#))
        let resListResult = try XCTUnwrap(resListResp["result"] as? [String: Any])
        let resources = try XCTUnwrap(resListResult["resources"] as? [[String: Any]])
        XCTAssertEqual(resources.first?["uri"] as? String, "clipvoice://clips")

        let resReadResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":8,"method":"resources/read","params":{"uri":"clipvoice://clips"}}"#))
        let resReadResult = try XCTUnwrap(resReadResp["result"] as? [String: Any])
        let contents = try XCTUnwrap(resReadResult["contents"] as? [[String: Any]])
        XCTAssertTrue((contents.first?["text"] as? String)?.contains("clip-1") ?? false)

        // 10. parse error
        let parseErrResp = try decodeResponse(server.handleLine("{not-json"))
        let errObj = try XCTUnwrap(parseErrResp["error"] as? [String: Any])
        XCTAssertEqual(errObj["code"] as? Int, -32700)
    }

    func testMalformedAndExtremeNumericArgumentsKeepServerAlive() throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipStore(fileURL: url)
        store.ingest("https://example.com/safe")
        let server = ClipVoiceMCPServerHandler(store: store)

        let badRequests = [
            #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"list_clips","arguments":{"limit":1e100}}}"#,
            #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"list_clips","arguments":{"limit":-5}}}"#,
            #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"list_clips","arguments":{"limit":1.5}}}"#,
            #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"list_clips","arguments":{"limit":"abc"}}}"#,
            #"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"list_clips","arguments":{"kind":"invalid-kind"}}}"#,
            #"{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"search_clips","arguments":{"query":"safe","limit":1e308}}}"#
        ]

        for req in badRequests {
            let resp = try decodeResponse(server.handleLine(req))
            let result = try XCTUnwrap(resp["result"] as? [String: Any])
            XCTAssertEqual(result["isError"] as? Bool, true, "Expected isError=true for malformed request: \(req)")
        }

        // Verify server remains healthy and serves subsequent valid calls.
        let healthyResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip-1"}}}"#))
        let healthyResult = try XCTUnwrap(healthyResp["result"] as? [String: Any])
        XCTAssertEqual(healthyResult["isError"] as? Bool, false)
        let text = try XCTUnwrap((healthyResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains("https://example.com/safe"))
    }

    func testMCPActivitySignalEmittedOnlyOnClipboardDataReadsWithoutLeakingPayload() throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipStore(fileURL: url)
        store.ingest("https://secret-internal.example.com/token=xyz123")
        let server = ClipVoiceMCPServerHandler(store: store)
        let activityFile = MCPActivitySignal.activityFileURL(for: url)

        // Metadata/handshake/error methods must NOT emit clipboard activity signals.
        _ = server.handleLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#)
        _ = server.handleLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        _ = server.handleLine(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        _ = server.handleLine(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        _ = server.handleLine(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)
        _ = server.handleLine(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_clips","arguments":{"limit":1e100}}}"#)
        XCTAssertFalse(FileManager.default.fileExists(atPath: activityFile.path))

        // Actual clipboard data access across all 5 operations emits sanitized activity signals.
        let expectedCalls: [(String, MCPActivityOperation)] = [
            (#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"list_clips","arguments":{}}}"#, .listClips),
            (#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip-1"}}}"#, .getClip),
            (#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"search_clips","arguments":{"query":"secret-internal"}}}"#, .searchClips),
            (#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_latest_clip","arguments":{}}}"#, .getLatestClip),
            (#"{"jsonrpc":"2.0","id":10,"method":"resources/read","params":{"uri":"clipvoice://clips"}}"#, .readResource)
        ]

        var seenEventIDs = Set<String>()
        for (line, expectedOp) in expectedCalls {
            _ = server.handleLine(line)
            let event = try XCTUnwrap(MCPActivitySignal.readLatest(for: url))
            XCTAssertEqual(event.operation, expectedOp)
            XCTAssertTrue(seenEventIDs.insert(event.eventID).inserted, "Expected unique eventID for \(expectedOp)")

            // Signal file must contain zero clipboard payload, queries, or item IDs.
            let rawSignal = try String(contentsOf: activityFile, encoding: .utf8)
            XCTAssertFalse(rawSignal.contains("secret-internal"))
            XCTAssertFalse(rawSignal.contains("xyz123"))
            XCTAssertFalse(rawSignal.contains("clip-1"))
        }
        XCTAssertEqual(seenEventIDs.count, 5)
    }

    func testMCPWriteClipMutatesIsolatedPasteboardAndDeduplicates() throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipStore(fileURL: url)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        let server = ClipVoiceMCPServerHandler(store: store, pasteboard: pb)
        let payload = "  let x = 1\n  let y = 2  "
        let req = #"{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"write_clip","arguments":{"content":"  let x = 1\n  let y = 2  "}}}"#
        let resp = try decodeResponse(server.handleLine(req))
        let result = try XCTUnwrap(resp["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains("\"clip-1\""))
        XCTAssertTrue(text.contains("\"created\""))

        XCTAssertEqual(pb.string(forType: .string), payload)

        // Activity signal contains targetItemID clip-1 and zero payload text
        let event = try XCTUnwrap(MCPActivitySignal.readLatest(for: url))
        XCTAssertEqual(event.operation, .writeClip)
        XCTAssertEqual(event.targetItemID, "clip-1")
        let rawSignal = try String(contentsOf: MCPActivitySignal.activityFileURL(for: url), encoding: .utf8)
        XCTAssertFalse(rawSignal.contains("let x = 1"))

        // Repeat identical write -> preserves clip-1 and reports updated
        let resp2 = try decodeResponse(server.handleLine(req))
        let result2 = try XCTUnwrap(resp2["result"] as? [String: Any])
        let text2 = try XCTUnwrap((result2["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text2.contains("\"clip-1\""))
        XCTAssertTrue(text2.contains("\"updated\""))
    }

    private func makeTestPNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func testMCPImageReadReturnsImageBlockAndListOmitsBase64() throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ClipStore(fileURL: url)
        let pngData = try makeTestPNGData(width: 96, height: 48)
        _ = store.ingestImage(pngData)
        _ = store.ingest("plain text entry")

        let server = ClipVoiceMCPServerHandler(store: store)

        // list_clips(kind: "image") must return metadata WITHOUT base64 data
        let listResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"list_clips","arguments":{"kind":"image"}}}"#))
        let listResult = try XCTUnwrap(listResp["result"] as? [String: Any])
        let listText = try XCTUnwrap((listResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(listText.contains("clip-1"))
        XCTAssertTrue(listText.contains("\"width\" : 96"))
        XCTAssertFalse(listText.contains(pngData.base64EncodedString()))

        // get_clip(id: "clip-1") must return text metadata block + standard MCP image block
        let getResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip-1"}}}"#))
        let getResult = try XCTUnwrap(getResp["result"] as? [String: Any])
        XCTAssertEqual(getResult["isError"] as? Bool, false)
        let blocks = try XCTUnwrap(getResult["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["type"] as? String, "image")
        XCTAssertEqual(blocks[1]["mimeType"] as? String, "image/png")

        let decodedBase64 = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(blocks[1]["data"] as? String)))
        let prepared = try ImageAssetStore.prepareCanonicalPNG(from: decodedBase64).get()
        XCTAssertEqual(prepared.width, 96)
        XCTAssertEqual(prepared.height, 48)
    }

    func testMCPWriteImageValidatesLocalFileMutatesPasteboardAndRejectsRemoteURL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipvoice-mcp-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("history.json")
        let imgFile = dir.appendingPathComponent("sample.png")
        let pngData = try makeTestPNGData(width: 64, height: 64)
        try pngData.write(to: imgFile)

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        let store = ClipStore(fileURL: storeURL)
        let server = ClipVoiceMCPServerHandler(store: store, pasteboard: pb)

        // Reject remote URLs
        let remoteResp = try decodeResponse(server.handleLine(#"{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"write_image","arguments":{"file_path":"https://example.com/a.png"}}}"#))
        let remoteResult = try XCTUnwrap(remoteResp["result"] as? [String: Any])
        XCTAssertEqual(remoteResult["isError"] as? Bool, true)

        // Accept valid local file
        let req = "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"tools/call\",\"params\":{\"name\":\"write_image\",\"arguments\":{\"file_path\":\"\(imgFile.path)\"}}}"
        let writeResp = try decodeResponse(server.handleLine(req))
        let writeResult = try XCTUnwrap(writeResp["result"] as? [String: Any])
        XCTAssertEqual(writeResult["isError"] as? Bool, false)
        let text = try XCTUnwrap((writeResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains("\"clip-1\""))
        XCTAssertTrue(text.contains("\"image\""))
        XCTAssertNotNil(pb.data(forType: .png))

        let event = try XCTUnwrap(MCPActivitySignal.readLatest(for: storeURL))
        XCTAssertEqual(event.operation, .writeImage)
        XCTAssertFalse(event.operation.isMCPAccess)
        XCTAssertTrue(event.operation.isIncomingWrite)
    }
}
