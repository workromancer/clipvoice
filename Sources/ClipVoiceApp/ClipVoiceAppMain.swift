import AppKit
import SwiftUI
import ClipVoiceCore

struct AppLaunchOptions {
    var storePath: String?
    var hudOnLaunch: Bool = true
    var noHotkey: Bool = false
    var testMode: Bool = false
    var locale: String?

    static func parse(_ arguments: [String]) -> AppLaunchOptions {
        var opts = AppLaunchOptions()
        var idx = 0
        while idx < arguments.count {
            let arg = arguments[idx]
            switch arg {
            case "--store":
                if idx + 1 < arguments.count {
                    opts.storePath = arguments[idx + 1]
                    idx += 2
                } else {
                    idx += 1
                }
            case "--locale":
                if idx + 1 < arguments.count {
                    opts.locale = arguments[idx + 1]
                    idx += 2
                } else {
                    idx += 1
                }
            case "--hud-on-launch":
                opts.hudOnLaunch = true
                idx += 1
            case "--hidden-on-launch":
                opts.hudOnLaunch = false
                idx += 1
            case "--no-hotkey":
                opts.noHotkey = true
                idx += 1
            case "--test-mode":
                opts.testMode = true
                idx += 1
            default:
                idx += 1
            }
        }
        return opts
    }
}

@main
@MainActor
final class ClipVoiceAppDelegate: NSObject, NSApplicationDelegate {
    private var options = AppLaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
    private var store: ClipStore!
    private var viewModel: ClipVoiceViewModel!
    private var monitor: ClipboardMonitor!
    private var mcpActivityMonitor: MCPActivityMonitor!
    private var hotKeyManager: GlobalHotKeyManager?
    private var hudPanel: FloatingHUDPanel?
    private var statusBarController: StatusBarController?
    private var keyMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = ClipVoiceAppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let locale = options.locale {
            L10n.overrideLocaleIdentifier = locale
        }

        // Menu-bar + floating HUD accessory app (does not clutter Dock unless testMode needs visibility).
        NSApp.setActivationPolicy(options.testMode ? .regular : .accessory)

        let storeURL = StorePathResolver.resolve(cliArgument: options.storePath)
        store = ClipStore(fileURL: storeURL)
        viewModel = ClipVoiceViewModel(store: store, hotkeyEnabled: !options.noHotkey)

        monitor = ClipboardMonitor(store: store) { [weak self] in
            self?.viewModel.refreshFromStore()
        }

        mcpActivityMonitor = MCPActivityMonitor(storeFileURL: storeURL) { [weak self] event in
            // Signal active state without opening or focusing a hidden HUD.
            self?.viewModel.recordMCPActivity(event)
        }

        let hostingView = NSHostingView(rootView: HUDView(viewModel: viewModel))
        let panel = FloatingHUDPanel(contentView: hostingView, autosaveFrame: !options.testMode)
        panel.onEscapePressed = { [weak self] in
            self?.hideHUD()
        }
        hudPanel = panel

        viewModel.onCopyToPasteboard = { [weak self] text in
            self?.monitor.writeToPasteboardAndSuppressReingest(text)
        }
        viewModel.onTogglePin = { [weak self] pinned in
            self?.hudPanel?.setPinned(pinned)
        }
        viewModel.onToggleHotkey = { [weak self] enabled in
            guard let self else { return }
            if enabled && !self.options.noHotkey {
                self.hotKeyManager?.register()
            } else {
                self.hotKeyManager?.unregister()
            }
        }
        viewModel.onHideHUD = { [weak self] in
            self?.hideHUD()
        }
        viewModel.onStateChanged = { [weak self] in
            self?.statusBarController?.updateButtonAppearance()
        }

        statusBarController = StatusBarController(
            viewModel: viewModel,
            isHUDVisible: { [weak self] in
                self?.hudPanel?.isVisible ?? false
            },
            onToggleHUD: { [weak self] in
                self?.toggleHUD()
            },
            onShowSetup: { [weak self] in
                self?.showHUD()
                self?.viewModel.showSetupSheet = true
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        if !options.noHotkey {
            let manager = GlobalHotKeyManager { [weak self] in
                self?.toggleHUD()
            }
            manager.register()
            hotKeyManager = manager
        }

        installLocalKeyboardMonitor()
        monitor.start()
        mcpActivityMonitor.start()

        if options.hudOnLaunch {
            showHUD()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        mcpActivityMonitor?.stop()
        hotKeyManager?.unregister()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHUD()
        return true
    }

    private func showHUD() {
        guard let panel = hudPanel else { return }
        viewModel.refreshFromStore()
        if options.testMode {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hideHUD() {
        hudPanel?.orderOut(nil)
    }

    private func toggleHUD() {
        guard let panel = hudPanel else { return }
        if panel.isVisible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    private func installLocalKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.hudPanel, panel.isVisible, panel.isKeyWindow else {
                return event
            }
            let isTextFieldEditing = panel.firstResponder is NSTextView
            switch event.keyCode {
            case 125: // Down arrow
                if !isTextFieldEditing {
                    self.viewModel.selectNext()
                    return nil
                }
            case 126: // Up arrow
                if !isTextFieldEditing {
                    self.viewModel.selectPrevious()
                    return nil
                }
            case 36: // Return
                if !isTextFieldEditing && !self.viewModel.showSetupSheet {
                    self.viewModel.copySelected()
                    return nil
                }
            case 51: // Delete / Backspace
                if !isTextFieldEditing && !self.viewModel.showSetupSheet {
                    self.viewModel.deleteSelected()
                    return nil
                }
            case 53: // Escape
                if !self.viewModel.showSetupSheet {
                    self.hideHUD()
                    return nil
                }
            default:
                break
            }
            return event
        }
    }
}
