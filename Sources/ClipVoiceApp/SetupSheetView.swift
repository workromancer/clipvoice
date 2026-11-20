import SwiftUI
import ClipVoiceCore

struct SetupSheetView: View {
    @ObservedObject var viewModel: ClipVoiceViewModel
    @Environment(\.dismiss) private var dismiss

    private var mcpBinaryPath: String {
        let bundled = "/Applications/ClipVoice.app/Contents/MacOS/clipvoice-mcp"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let sibling = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("clipvoice-mcp")
            .path
        if let sibling, FileManager.default.isExecutableFile(atPath: sibling) {
            return sibling
        }
        return bundled
    }

    private var cliBinaryPath: String {
        let bundled = "/Applications/ClipVoice.app/Contents/MacOS/clipvoice-cli"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let sibling = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("clipvoice-cli")
            .path
        if let sibling, FileManager.default.isExecutableFile(atPath: sibling) {
            return sibling
        }
        return bundled
    }

    private var mcpConfigSnippet: String {
        """
        {
          "mcpServers": {
            "clipvoice": {
              "command": "\(mcpBinaryPath)",
              "args": []
            }
          }
        }
        """
    }

    private var skillInstallCommand: String {
        "\"\(cliBinaryPath)\" install-skill --target codex"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("setup.title"))
                        .font(.system(size: 16, weight: .bold))
                    Text(L10n.tr("setup.subtitle"))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(L10n.tr("setup.done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("setup-done-button")
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsGroup

                    codeSection(
                        title: L10n.tr("setup.mcp_config_title"),
                        code: mcpConfigSnippet,
                        copyLabel: L10n.tr("setup.copy_mcp_config"),
                        feedbackKey: "mcp-json"
                    )

                    codeSection(
                        title: L10n.tr("setup.skill_title"),
                        code: skillInstallCommand,
                        copyLabel: L10n.tr("setup.copy_skill_cmd"),
                        feedbackKey: "skill-cmd"
                    )

                    codeSection(
                        title: L10n.tr("setup.cli_title"),
                        code: "\"\(cliBinaryPath)\" list --kind url\n\"\(cliBinaryPath)\" get clip-1 --raw",
                        copyLabel: L10n.tr("action.copy"),
                        feedbackKey: "cli-cmd"
                    )

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text(L10n.tr("setup.privacy_note"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
                }
            }
        }
        .padding(16)
        .frame(width: 460, height: 500)
        .preferredColorScheme(.dark)
    }

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("setup.history_cap"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.maxItems },
                    set: { viewModel.setMaxItems($0) }
                )) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("200").tag(200)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            Toggle(isOn: Binding(
                get: { viewModel.hotkeyEnabled },
                set: { viewModel.setHotkeyEnabled($0) }
            )) {
                Text(L10n.tr("setup.global_hotkey"))
                    .font(.system(size: 12, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("setup.store_path"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(viewModel.store.fileURL.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
    }

    private func codeSection(title: String, code: String, copyLabel: String, feedbackKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(viewModel.copiedFeedbackID == feedbackKey ? L10n.tr("action.copied") : copyLabel) {
                    viewModel.copyText(code, feedbackKey: feedbackKey)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Text(code)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }
}
