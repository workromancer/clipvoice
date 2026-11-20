import AppKit
import ClipVoiceCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let viewModel: ClipVoiceViewModel
    private let isHUDVisible: () -> Bool
    private let onToggleHUD: () -> Void
    private let onShowSetup: () -> Void
    private let onQuit: () -> Void

    init(
        viewModel: ClipVoiceViewModel,
        isHUDVisible: @escaping () -> Bool,
        onToggleHUD: @escaping () -> Void,
        onShowSetup: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.viewModel = viewModel
        self.isHUDVisible = isHUDVisible
        self.onToggleHUD = onToggleHUD
        self.onShowSetup = onShowSetup
        self.onQuit = onQuit
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        updateButtonAppearance()
    }

    func updateButtonAppearance() {
        guard let button = statusItem.button else { return }
        let symbolName = viewModel.isPaused ? "pause.circle" : "waveform"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: L10n.tr("app.name"))
        image?.isTemplate = true
        button.image = image
        button.toolTip = viewModel.isPaused
            ? "\(L10n.tr("app.name")) — \(L10n.tr("status.paused"))"
            : "\(L10n.tr("app.name")) — \(L10n.tr("status.live"))"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleTitle = isHUDVisible() ? L10n.tr("action.hide_hud") : L10n.tr("action.show_hud")
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleHUD), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let hotkeyLabel = NSMenuItem(title: L10n.tr("menu.hotkey_label"), action: nil, keyEquivalent: "")
        hotkeyLabel.isEnabled = false
        menu.addItem(hotkeyLabel)

        menu.addItem(.separator())

        let pauseTitle = viewModel.isPaused ? L10n.tr("action.resume") : L10n.tr("action.pause")
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(handleTogglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let recentMenu = NSMenu()
        let recentItems = Array(viewModel.allItems.prefix(8))
        if recentItems.isEmpty {
            let empty = NSMenuItem(title: L10n.tr("menu.no_recent"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for item in recentItems {
                let title = "[\(item.id)] \(item.preview.prefix(48))"
                let entry = NSMenuItem(title: title, action: #selector(handleCopyRecent(_:)), keyEquivalent: "")
                entry.representedObject = item.id
                entry.target = self
                recentMenu.addItem(entry)
            }
        }
        let recentParent = NSMenuItem(title: L10n.tr("menu.recent_clips"), action: nil, keyEquivalent: "")
        recentParent.submenu = recentMenu
        menu.addItem(recentParent)

        menu.addItem(.separator())

        let setupItem = NSMenuItem(title: L10n.tr("action.setup"), action: #selector(handleShowSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        let clearItem = NSMenuItem(title: L10n.tr("action.clear"), action: #selector(handleClear), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !viewModel.allItems.isEmpty
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.tr("action.quit"), action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func handleToggleHUD() {
        onToggleHUD()
    }

    @objc private func handleTogglePause() {
        viewModel.togglePause()
        updateButtonAppearance()
    }

    @objc private func handleCopyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = viewModel.allItems.first(where: { $0.id == id }) else {
            return
        }
        viewModel.copyItem(item)
    }

    @objc private func handleShowSetup() {
        onShowSetup()
    }

    @objc private func handleClear() {
        viewModel.clearAll()
        updateButtonAppearance()
    }

    @objc private func handleQuit() {
        onQuit()
    }
}
