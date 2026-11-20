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

func collectNodes(root: AXUIElement, maxDepth: Int = 18) -> [AXNode] {
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

func waitForNode(window: AXUIElement, timeout: TimeInterval = 5.0, matching predicate: (AXNode) -> Bool) -> AXNode? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let match = collectNodes(root: window).first(where: predicate) {
            return match
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    return nil
}

func waitUntilGone(window: AXUIElement, timeout: TimeInterval = 4.0, matching predicate: (AXNode) -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !collectNodes(root: window).contains(where: predicate) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.15)
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

func fail(_ message: String) -> Never {
    fputs("AX_E2E_FAIL: \(message)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: ax_e2e.swift <mode: full|ko> <pid>\n", stderr)
    exit(2)
}

let mode = CommandLine.arguments[1]
guard let pid = Int32(CommandLine.arguments[2]) else {
    fail("Invalid PID")
}

guard AXIsProcessTrusted() else {
    fail("AXIsProcessTrusted() returned false")
}

let appEl = AXUIElementCreateApplication(pid)
guard let window = waitForWindow(appElement: appEl, timeout: 10.0) else {
    fail("HUD window did not appear for pid \(pid)")
}

if mode == "ko" {
    guard let badge = waitForNode(window: window, timeout: 4.0, matching: {
        $0.identifier == "status-badge" || $0.label.contains("수신 중") || $0.value.contains("수신 중")
    }) else {
        let dump = collectNodes(root: window).map { "\($0.role)[id=\($0.identifier),title=\($0.title),val=\($0.value),desc=\($0.label)]" }.joined(separator: "\n")
        fail("Korean localized status badge not found. Tree:\n\(dump)")
    }
    print("AX_KO_VERIFIED: id=\(badge.identifier) label=\(badge.label) value=\(badge.value)")
    exit(0)
}

// 1. Verify initial controls exist
for requiredID in ["pause-button", "filter-all", "filter-url", "filter-text", "search-field", "setup-button", "close-button"] {
    guard waitForNode(window: window, timeout: 4.0, matching: { $0.identifier == requiredID }) != nil else {
        fail("Missing HUD control: \(requiredID)")
    }
}
print("AX_STEP_1: Initial HUD controls verified")

// 2. pbcopy URL -> verify clip-1 appears in HUD
setPasteboard("https://example.com/clipvoice/pr-42")
guard let clip1Node = waitForNode(window: window, timeout: 5.0, matching: { $0.identifier == "clip-id-clip-1" }) else {
    fail("clip-1 did not appear in HUD after pbcopy")
}
print("AX_STEP_2: Captured clip-1 visible in HUD (y=\(nodeCenterY(clip1Node.element) ?? -1))")

// 3. pbcopy text -> verify clip-2 appears above clip-1 (newest-first) and clip-1 keeps its ID
setPasteboard("let clipVoiceReady = true")
guard let clip2Node = waitForNode(window: window, timeout: 5.0, matching: { $0.identifier == "clip-id-clip-2" }),
      let clip1After = waitForNode(window: window, timeout: 2.0, matching: { $0.identifier == "clip-id-clip-1" }) else {
    fail("clip-2 or clip-1 missing after second copy")
}
if let y2 = nodeCenterY(clip2Node.element), let y1 = nodeCenterY(clip1After.element) {
    guard y2 < y1 else {
        fail("Expected clip-2 (y=\(y2)) to appear above clip-1 (y=\(y1)) in newest-first order")
    }
    print("AX_STEP_3: Newest-first verified (clip-2 y=\(y2) < clip-1 y=\(y1)), clip-1 ID preserved")
}

// 4. Re-copy URL -> clip-1 bumps above clip-2 while keeping stable ID clip-1
setPasteboard("https://example.com/clipvoice/pr-42")
let bumpedDeadline = Date().addingTimeInterval(5.0)
var bumpedOK = false
while Date() < bumpedDeadline {
    let nodes = collectNodes(root: window)
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

// 5. Filter tab test: Links hides clip-2, All restores clip-2
guard let filterURL = waitForNode(window: window, timeout: 2.0, matching: { $0.identifier == "filter-url" }),
      press(filterURL) else {
    fail("Could not press filter-url")
}
guard waitUntilGone(window: window, timeout: 3.0, matching: { $0.identifier == "clip-id-clip-2" }) else {
    fail("clip-2 was still visible under Links filter")
}
guard let filterAll = waitForNode(window: window, timeout: 2.0, matching: { $0.identifier == "filter-all" }),
      press(filterAll),
      waitForNode(window: window, timeout: 3.0, matching: { $0.identifier == "clip-id-clip-2" }) != nil else {
    fail("Restoring All filter did not restore clip-2")
}
print("AX_STEP_5: Filter tabs (Links / All) verified via AXPress")

// 6. Pause capture -> copy ignored -> Resume capture -> new clip-3 captured
guard let pauseBtn = waitForNode(window: window, timeout: 2.0, matching: { $0.identifier == "pause-button" }),
      press(pauseBtn) else {
    fail("Could not press pause-button")
}
guard waitForNode(window: window, timeout: 3.0, matching: { $0.identifier == "resume-banner-button" }) != nil else {
    fail("Paused banner did not appear")
}
setPasteboard("ignored-while-paused-e2e")
Thread.sleep(forTimeInterval: 0.8)
if collectNodes(root: window).contains(where: { $0.identifier == "clip-id-clip-3" }) {
    fail("Clip was captured while paused!")
}
guard let resumeBtn = waitForNode(window: window, timeout: 2.0, matching: { $0.identifier == "pause-button" }),
      press(resumeBtn) else {
    fail("Could not press pause-button to resume")
}
setPasteboard("captured-after-resume-e2e")
guard waitForNode(window: window, timeout: 5.0, matching: { $0.identifier == "clip-id-clip-3" }) != nil else {
    fail("clip-3 did not appear after resuming capture")
}
print("AX_STEP_6: Pause/Resume verified via AXPress")

// 7. Delete clip-2 via AX button
guard let delBtn = waitForNode(window: window, timeout: 2.0, matching: { $0.identifier == "delete-button-clip-2" }),
      press(delBtn) else {
    fail("Could not press delete-button-clip-2")
}
guard waitUntilGone(window: window, timeout: 3.0, matching: { $0.identifier == "clip-id-clip-2" }) else {
    fail("clip-2 was not deleted")
}
print("AX_STEP_7: Delete clip-2 verified via AXPress")
