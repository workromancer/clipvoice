import Foundation
import ApplicationServices
import AppKit

struct AXNode {
    let element: AXUIElement
    let role: String
    let identifier: String
    let title: String
    let value: String
    let label: String
}

func stringAttr(_ el: AXUIElement, _ attr: String) -> String {
    var val: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &val) == .success, let val else {
        return ""
    }
    if let s = val as? String { return s }
    if let n = val as? NSNumber { return n.stringValue }
    return ""
}

func children(of el: AXUIElement) -> [AXUIElement] {
    var val: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &val) == .success,
          let arr = val as? [AXUIElement] else {
        return []
    }
    return arr
}

func collectNodes(root: AXUIElement, maxDepth: Int = 20) -> [AXNode] {
    var result: [AXNode] = []
    func walk(_ el: AXUIElement, depth: Int) {
        if depth > maxDepth { return }
        let node = AXNode(
            element: el,
            role: stringAttr(el, kAXRoleAttribute),
            identifier: stringAttr(el, kAXIdentifierAttribute),
            title: stringAttr(el, kAXTitleAttribute),
            value: stringAttr(el, kAXValueAttribute),
            label: stringAttr(el, kAXDescriptionAttribute)
        )
        result.append(node)
        for child in children(of: el) {
            walk(child, depth: depth + 1)
        }
    }
    walk(root, depth: 0)
    return result
}

func collectAllAppNodes(appEl: AXUIElement) -> [AXNode] {
    var nodes: [AXNode] = []
    var val: CFTypeRef?
    if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &val) == .success,
       let windows = val as? [AXUIElement] {
        for w in windows {
            nodes.append(contentsOf: collectNodes(root: w))
        }
    }
    return nodes
}

func waitForWindow(appElement: AXUIElement, timeout: TimeInterval = 8.0) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &val) == .success,
           let windows = val as? [AXUIElement],
           let first = windows.first {
            return first
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    return nil
}

func waitForNode(appEl: AXUIElement, timeout: TimeInterval = 5.0, matching predicate: (AXNode) -> Bool) -> AXNode? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let match = collectAllAppNodes(appEl: appEl).first(where: predicate) {
            return match
        }
        Thread.sleep(forTimeInterval: 0.12)
    }
    return nil
}

func waitUntilGone(appEl: AXUIElement, timeout: TimeInterval = 4.0, matching predicate: (AXNode) -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !collectAllAppNodes(appEl: appEl).contains(where: predicate) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.12)
    }
    return false
}

func press(_ node: AXNode) -> Bool {
    AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success
}

func setPasteboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

func nodeCenterY(_ el: AXUIElement) -> CGFloat? {
    var posVal: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posVal) == .success,
          let axVal = posVal else { return nil }
    var pt = CGPoint.zero
    if AXValueGetValue(axVal as! AXValue, .cgPoint, &pt) {
        return pt.y
    }
    return nil
}

func windowAXFrame(_ window: AXUIElement) -> CGRect? {
    var posVal: CFTypeRef?
    var sizeVal: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal) == .success,
          let pVal = posVal, let sVal = sizeVal else { return nil }
    var pt = CGPoint.zero
    var sz = CGSize.zero
    guard AXValueGetValue(pVal as! AXValue, .cgPoint, &pt),
          AXValueGetValue(sVal as! AXValue, .cgSize, &sz) else { return nil }
    return CGRect(origin: pt, size: sz)
}

func setWindowSize(_ window: AXUIElement, size: CGSize) -> Bool {
    var sz = size
    guard let val = AXValueCreate(.cgSize, &sz) else { return false }
    return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, val) == .success
}

func fail(_ message: String) -> Never {
    fputs("AX_E2E_FAIL: \(message)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: ax_e2e.swift <mode> <pid> [arg]\n", stderr)
    exit(2)
}

let mode = CommandLine.arguments[1]
guard let pid = Int32(CommandLine.arguments[2]) else {
    fail("Invalid PID")
}
let extraArg = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : ""

guard AXIsProcessTrusted() else {
    fail("AXIsProcessTrusted() returned false")
}

let appEl = AXUIElementCreateApplication(pid)

if mode == "check-hidden" {
    Thread.sleep(forTimeInterval: 1.0)
    var val: CFTypeRef?
    if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &val) == .success,
       let windows = val as? [AXUIElement], !windows.isEmpty {
        fail("Expected hidden HUD to stay closed on MCP access, but found \(windows.count) window(s)")
    }
    print("AX_HIDDEN_VERIFIED: HUD remained closed during MCP access")
    exit(0)
}

guard let window = waitForWindow(appElement: appEl, timeout: 10.0) else {
    fail("HUD window did not appear for pid \(pid)")
}

switch mode {
case "ko":
    guard let badge = waitForNode(appEl: appEl, timeout: 4.0, matching: {
        $0.identifier == "status-badge" || $0.label.contains("수신 중") || $0.value.contains("수신 중")
    }) else {
        fail("Korean localized status badge not found")
    }
    print("AX_KO_VERIFIED: id=\(badge.identifier) label=\(badge.label) value=\(badge.value)")

case "check-no-mcp":
    let nodes = collectAllAppNodes(appEl: appEl)
    if nodes.contains(where: { $0.identifier == "mcp-activity-badge" || $0.identifier == "mcp-pulse-border" }) {
        fail("Unexpected MCP activity indicator present when none should be active")
    }
    print("AX_NO_MCP_VERIFIED: No stale or metadata-triggered MCP activity")

case "wait-mcp-on":
    let timeout = Double(extraArg) ?? 6.0
    guard let badge = waitForNode(appEl: appEl, timeout: timeout, matching: { $0.identifier == "mcp-activity-badge" }),
          waitForNode(appEl: appEl, timeout: 1.0, matching: { $0.identifier == "mcp-pulse-border" }) != nil else {
        fail("MCP pulse border or activity badge did not appear")
    }
    print("AX_MCP_ON_VERIFIED: badge='\(badge.label)'")

case "wait-mcp-off":
    let timeout = Double(extraArg) ?? 6.0
    guard waitUntilGone(appEl: appEl, timeout: timeout, matching: { $0.identifier == "mcp-activity-badge" || $0.identifier == "mcp-pulse-border" }) else {
        fail("MCP activity indicator did not clear after timeout")
    }
    print("AX_MCP_OFF_VERIFIED: Pulse border and MCP badge cleared cleanly")

case "wait-incoming":
    let expectedID = extraArg
    guard waitForNode(appEl: appEl, timeout: 4.0, matching: { $0.identifier == "incoming-indicator-\(expectedID)" }) != nil,
          waitForNode(appEl: appEl, timeout: 1.0, matching: { $0.identifier == "clip-id-\(expectedID)" }) != nil else {
        fail("Incoming indicator or row missing for \(expectedID)")
    }
    print("AX_INCOMING_VERIFIED: \(expectedID) highlighted & visible")

case "press-id":
    guard let btn = waitForNode(appEl: appEl, timeout: 4.0, matching: { $0.identifier == extraArg }),
          press(btn) else {
        fail("Could not press element with identifier '\(extraArg)'")
    }
    print("AX_PRESSED: \(extraArg)")

case "set-search":
    guard let searchNode = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "search-field" }) else {
        fail("Missing search-field")
    }
    AXUIElementSetAttributeValue(searchNode.element, kAXValueAttribute as CFString, extraArg as CFTypeRef)
    print("AX_SEARCH_SET: '\(extraArg)'")

case "verify-image-copy":
    let targetID = extraArg
    guard waitForNode(appEl: appEl, timeout: 5.0, matching: { $0.identifier == "clip-image-thumb-\(targetID)" }) != nil else {
        fail("Image thumbnail missing for \(targetID)")
    }
    guard let row = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "clip-row-\(targetID)" }),
          press(row) else {
        fail("Could not select image row \(targetID)")
    }
    guard let copyBtn = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "copy-button-\(targetID)" }),
          press(copyBtn) else {
        fail("Could not press copy-button-\(targetID)")
    }
    Thread.sleep(forTimeInterval: 0.3)
    let pb = NSPasteboard.general
    guard let pngOut = pb.data(forType: .png), !pngOut.isEmpty else {
        fail("Expected actual PNG data on NSPasteboard after copying \(targetID)")
    }
    print("AX_IMAGE_COPY_VERIFIED: \(targetID) -> \(pngOut.count) PNG bytes on NSPasteboard")

case "open-inspector":
    let targetID = extraArg
    guard let row = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "clip-row-\(targetID)" }),
          press(row) else {
        fail("Could not select row \(targetID)")
    }
    guard let inspectBtn = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "copy-voice-prompt-button" }),
          press(inspectBtn) else {
        fail("Could not press Inspect button")
    }
    guard waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "inspector-image-preview" }) != nil else {
        fail("Inspector image preview did not appear")
    }
    print("AX_IMAGE_INSPECTOR_VERIFIED: \(targetID)")

case "placement-and-resize":
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
    let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

    // Open Display Settings popover to access Left / Float / Right presets
    guard let displayBtn1 = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "display-settings-button" }),
          press(displayBtn1) else {
        fail("Could not open display-settings-button")
    }

    // 1. Left dock preset
    guard let dockLeft = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "dock-left-button" }),
          press(dockLeft) else {
        fail("Could not press dock-left-button")
    }
    Thread.sleep(forTimeInterval: 0.35)
    guard let leftFrame = windowAXFrame(window) else { fail("Could not read left docked frame") }
    let leftAppKitMinY = primaryHeight - (leftFrame.origin.y + leftFrame.size.height)
    guard abs(leftFrame.origin.x - (visible.minX + 10)) <= 3,
          abs(leftFrame.size.width - 300) <= 3,
          abs(leftAppKitMinY - (visible.minY + 10)) <= 3,
          abs(leftFrame.size.height - (visible.height - 20)) <= 3 else {
        fail("Left dock frame mismatch: ax=\(leftFrame) appKitMinY=\(leftAppKitMinY) visible=\(visible)")
    }
    print("AX_DOCK_LEFT_VERIFIED: frame=\(leftFrame)")

    // 2. Right dock preset
    guard let dockRight = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "dock-right-button" }),
          press(dockRight) else {
        fail("Could not press dock-right-button")
    }
    Thread.sleep(forTimeInterval: 0.35)
    guard let rightFrame = windowAXFrame(window) else { fail("Could not read right docked frame") }
    guard abs((rightFrame.origin.x + rightFrame.size.width) - (visible.maxX - 10)) <= 3,
          abs(rightFrame.size.width - 300) <= 3,
          abs(rightFrame.size.height - (visible.height - 20)) <= 3 else {
        fail("Right dock frame mismatch: ax=\(rightFrame) visible=\(visible)")
    }
    print("AX_DOCK_RIGHT_VERIFIED: frame=\(rightFrame)")

    // 3. Free resize down to slim 285px and confirm essential controls stay usable
    _ = press(displayBtn1) // close popover before checking list rows
    Thread.sleep(forTimeInterval: 0.2)
    _ = setWindowSize(window, size: CGSize(width: 285, height: 520))
    Thread.sleep(forTimeInterval: 0.25)
    guard let slimFrame = windowAXFrame(window), abs(slimFrame.size.width - 285) <= 6 else {
        fail("Free resize to 285px failed")
    }
    guard waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "clip-id-clip-1" }) != nil,
          waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "pause-button" }) != nil else {
        fail("Essential HUD controls missing at 285px slim width")
    }
    print("AX_SLIM_RESIZE_VERIFIED: width=\(slimFrame.size.width)")

    // 4. Floating preset restores >= 400px width
    guard press(displayBtn1),
          let dockFloat = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "dock-floating-button" }),
          press(dockFloat) else {
        fail("Could not press dock-floating-button")
    }
    Thread.sleep(forTimeInterval: 0.35)
    guard let floatFrame = windowAXFrame(window), floatFrame.size.width >= 400 else {
        fail("Floating preset did not restore >= 400px width")
    }
    _ = press(displayBtn1) // close popover cleanly
    Thread.sleep(forTimeInterval: 0.2)
    print("AX_FLOATING_RESTORED_VERIFIED: frame=\(floatFrame)")

case "opacity-set-75":
    guard let displayBtn = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "display-settings-button" }),
          press(displayBtn) else {
        fail("Could not press display-settings-button")
    }
    guard let preset75 = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "opacity-preset-75" }),
          press(preset75) else {
        fail("Could not press opacity-preset-75")
    }
    guard let label = waitForNode(appEl: appEl, timeout: 2.0, matching: {
        $0.identifier == "opacity-value-label" && ($0.value.contains("75%") || $0.label.contains("75%") || $0.title.contains("75%"))
    }) else {
        fail("Opacity label did not update to 75%")
    }
    print("AX_OPACITY_SET_VERIFIED: \(label.value)\(label.label)\(label.title)")

case "verify-opacity-75":
    guard let displayBtn = waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "display-settings-button" }),
          press(displayBtn) else {
        fail("Could not press display-settings-button on relaunch")
    }
    guard let label = waitForNode(appEl: appEl, timeout: 3.0, matching: {
        $0.identifier == "opacity-value-label" && ($0.value.contains("75%") || $0.label.contains("75%") || $0.title.contains("75%"))
    }) else {
        fail("Persisted opacity 75% not retained across relaunch")
    }
    print("AX_OPACITY_PERSISTED_VERIFIED: \(label.value)\(label.label)\(label.title)")

case "full":
    for requiredID in ["pause-button", "display-settings-button", "filter-all", "filter-url", "filter-text", "search-field", "setup-button", "close-button"] {
        guard waitForNode(appEl: appEl, timeout: 4.0, matching: { $0.identifier == requiredID }) != nil else {
            fail("Missing HUD control: \(requiredID)")
        }
    }
    print("AX_STEP_1: Initial HUD controls verified")

    setPasteboard("https://example.com/clipvoice/pr-42")
    guard let clip1Node = waitForNode(appEl: appEl, timeout: 5.0, matching: { $0.identifier == "clip-id-clip-1" }) else {
        fail("clip-1 did not appear in HUD after pbcopy")
    }
    print("AX_STEP_2: Captured clip-1 visible in HUD (y=\(nodeCenterY(clip1Node.element) ?? -1))")

    setPasteboard("let clipVoiceReady = true")
    guard let clip2Node = waitForNode(appEl: appEl, timeout: 5.0, matching: { $0.identifier == "clip-id-clip-2" }),
          let clip1After = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "clip-id-clip-1" }) else {
        fail("clip-2 or clip-1 missing after second copy")
    }
    if let y2 = nodeCenterY(clip2Node.element), let y1 = nodeCenterY(clip1After.element) {
        guard y2 < y1 else {
            fail("Expected clip-2 (y=\(y2)) to appear above clip-1 (y=\(y1)) in newest-first order")
        }
        print("AX_STEP_3: Newest-first verified (clip-2 y=\(y2) < clip-1 y=\(y1)), clip-1 ID preserved")
    }

    setPasteboard("https://example.com/clipvoice/pr-42")
    let bumpedDeadline = Date().addingTimeInterval(5.0)
    var bumpedOK = false
    while Date() < bumpedDeadline {
        let nodes = collectAllAppNodes(appEl: appEl)
        if let n1 = nodes.first(where: { $0.identifier == "clip-id-clip-1" }),
           let n2 = nodes.first(where: { $0.identifier == "clip-id-clip-2" }),
           let y1 = nodeCenterY(n1.element),
           let y2 = nodeCenterY(n2.element),
           y1 < y2 {
            bumpedOK = true
            print("AX_STEP_4: Re-copy bumped clip-1 (y=\(y1)) above clip-2 (y=\(y2)) with unchanged stable ID")
            break
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    guard bumpedOK else {
        fail("Re-copying URL did not bump clip-1 above clip-2")
    }

    guard let filterURL = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "filter-url" }),
          press(filterURL) else {
        fail("Could not press filter-url")
    }
    guard waitUntilGone(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "clip-id-clip-2" }) else {
        fail("clip-2 was still visible under Links filter")
    }
    guard let filterAll = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "filter-all" }),
          press(filterAll),
          waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "clip-id-clip-2" }) != nil else {
        fail("Restoring All filter did not restore clip-2")
    }
    print("AX_STEP_5: Filter tabs (Links / All) verified via AXPress")

    guard let pauseBtn = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "pause-button" }),
          press(pauseBtn) else {
        fail("Could not press pause-button")
    }
    guard waitForNode(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "resume-banner-button" }) != nil else {
        fail("Paused banner did not appear")
    }
    setPasteboard("ignored-while-paused-e2e")
    Thread.sleep(forTimeInterval: 0.8)
    if collectAllAppNodes(appEl: appEl).contains(where: { $0.identifier == "clip-id-clip-3" }) {
        fail("Clip was captured while paused!")
    }
    guard let resumeBtn = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "pause-button" }),
          press(resumeBtn) else {
        fail("Could not press pause-button to resume")
    }
    setPasteboard("captured-after-resume-e2e")
    guard waitForNode(appEl: appEl, timeout: 5.0, matching: { $0.identifier == "clip-id-clip-3" }) != nil else {
        fail("clip-3 did not appear after resuming capture")
    }
    print("AX_STEP_6: Pause/Resume verified via AXPress")

    // Select clip-2 first so its row action glyphs appear, then delete clip-2
    guard let row2 = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "clip-row-clip-2" }),
          press(row2) else {
        fail("Could not select clip-row-clip-2")
    }
    guard let delBtn = waitForNode(appEl: appEl, timeout: 2.0, matching: { $0.identifier == "delete-button-clip-2" }),
          press(delBtn) else {
        fail("Could not press delete-button-clip-2")
    }
    guard waitUntilGone(appEl: appEl, timeout: 3.0, matching: { $0.identifier == "clip-id-clip-2" }) else {
        fail("clip-2 was not deleted")
    }
    print("AX_STEP_7: Delete clip-2 verified via AXPress")

default:
    fail("Unknown mode: \(mode)")
}
