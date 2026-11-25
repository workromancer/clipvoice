import AppKit
import SwiftUI
import ClipVoiceCore

@MainActor
final class FloatingHUDPanel: NSPanel, NSWindowDelegate {
    var onEscapePressed: (() -> Void)?
    private let preferences: AppPreferencesStore
    private var currentPlacementMode: WindowPlacementMode
    private var isApplyingPlacement = false
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    init(contentView: NSView, preferences: AppPreferencesStore) {
        self.preferences = preferences
        self.currentPlacementMode = preferences.placementMode

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = preferences.isPinned ? .floating : .normal
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.appearance = NSAppearance(named: .darkAqua)
        self.becomesKeyOnlyIfNeeded = true
        self.minSize = NSSize(width: AppPreferencesStore.minDockWidth, height: 400)
        self.maxSize = NSSize(width: 820, height: 1400)
        self.alphaValue = CGFloat(preferences.opacity)
        self.setAccessibilityIdentifier("clipvoice-hud-window")
        self.setAccessibilityTitle("ClipVoice")

        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        self.contentView = contentView
        self.delegate = self

        applyPlacement(preferences.placementMode, persistWidth: false)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileForScreenChange()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
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

    func applyOpacity(_ opacity: Double) {
        alphaValue = CGFloat(AppPreferencesStore.clampOpacity(opacity))
    }

    func applyPlacement(_ mode: WindowPlacementMode, persistWidth: Bool = true) {
        currentPlacementMode = mode
        let targetScreen = self.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let availableScreens = NSScreen.screens.map(\.visibleFrame)

        let targetFrame = AppPreferencesStore.targetFrame(
            for: mode,
            screenVisibleFrame: visible,
            dockWidth: preferences.dockWidth,
            savedFloatingFrame: preferences.savedFloatingFrame(),
            availableScreens: availableScreens.isEmpty ? [visible] : availableScreens
        )

        isApplyingPlacement = true
        setFrame(targetFrame, display: true, animate: false)
        contentView?.needsLayout = true
        displayIfNeeded()
        isApplyingPlacement = false

        if persistWidth && mode == .floating {
            preferences.saveFloatingFrame(targetFrame)
        }
    }

    func resetToDefaultFloating() {
        applyPlacement(.floating, persistWidth: true)
        applyOpacity(preferences.opacity)
    }

    func reconcileForScreenChange() {
        let visible = (self.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let availableScreens = NSScreen.screens.map(\.visibleFrame)
        switch currentPlacementMode {
        case .dockLeft, .dockRight:
            applyPlacement(currentPlacementMode, persistWidth: false)
        case .floating:
            if !AppPreferencesStore.isFrameSafeOnScreen(frame, availableScreens: availableScreens.isEmpty ? [visible] : availableScreens) {
                preferences.saveFloatingFrame(
                    AppPreferencesStore.targetFrame(
                        for: .floating,
                        screenVisibleFrame: visible,
                        dockWidth: preferences.dockWidth,
                        savedFloatingFrame: nil,
                        availableScreens: availableScreens
                    )
                )
                applyPlacement(.floating, persistWidth: false)
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingPlacement else { return }
        switch currentPlacementMode {
        case .floating:
            preferences.saveFloatingFrame(frame)
        case .dockLeft, .dockRight:
            let visible = (self.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let clampedWidth = AppPreferencesStore.clampDockWidth(frame.width, in: visible)
            preferences.dockWidth = clampedWidth
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingPlacement else { return }
        if currentPlacementMode == .floating {
            preferences.saveFloatingFrame(frame)
        }
    }
}
