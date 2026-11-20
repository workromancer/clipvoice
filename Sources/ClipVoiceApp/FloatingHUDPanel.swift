import AppKit
import SwiftUI

final class FloatingHUDPanel: NSPanel {
    var onEscapePressed: (() -> Void)?

    init(contentView: NSView, autosaveFrame: Bool = true) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 620),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.becomesKeyOnlyIfNeeded = true
        self.minSize = NSSize(width: 440, height: 480)
        self.maxSize = NSSize(width: 780, height: 960)
        self.setAccessibilityIdentifier("clipvoice-hud-window")
        self.setAccessibilityTitle(ClipVoiceCoreTitleFallback.title)

        // Hide standard traffic lights because the HUD uses custom header controls.
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        self.contentView = contentView
        if autosaveFrame {
            self.setFrameAutosaveName("ClipVoiceFloatingHUDFrame")
            if !self.setFrameUsingName("ClipVoiceFloatingHUDFrame") {
                positionNearTopRight()
            }
        } else {
            positionNearTopRight()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    func setPinned(_ pinned: Bool) {
        level = pinned ? .floating : .normal
    }

    func positionNearTopRight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width: CGFloat = 490
        let height: CGFloat = min(620, visible.height - 48)
        let x = visible.maxX - width - 24
        let y = visible.maxY - height - 24
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private enum ClipVoiceCoreTitleFallback {
    static let title = "ClipVoice"
}
