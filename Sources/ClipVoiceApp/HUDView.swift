import SwiftUI
import AppKit
import ClipVoiceCore

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct HUDView: View {
    @ObservedObject var viewModel: ClipVoiceViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Divider().opacity(0.25)

                searchAndFilterBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                if viewModel.isPaused {
                    pausedBanner
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }

                clipsListSection

                Divider().opacity(0.25)

                inspectorFooter
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .frame(minWidth: 400, minHeight: 460)
        .sheet(isPresented: $viewModel.showSetupSheet) {
            SetupSheetView(viewModel: viewModel)
        }
        .alert(L10n.tr("action.clear_confirm_title"), isPresented: $viewModel.showClearConfirmation) {
            Button(L10n.tr("action.clear"), role: .destructive) {
                viewModel.clearAll()
            }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("action.clear_confirm_message"))
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(L10n.tr("app.name"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    statusBadge
                }
                Text(L10n.tr("app.tagline"))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                HUDIconButton(
                    systemName: viewModel.isPinned ? "pin.fill" : "pin",
                    helpText: viewModel.isPinned ? L10n.tr("action.unpin") : L10n.tr("action.pin"),
                    tint: viewModel.isPinned ? .accentColor : .secondary,
                    accessibilityID: "pin-button"
                ) {
                    viewModel.togglePin()
                }

                HUDIconButton(
                    systemName: viewModel.isPaused ? "play.circle.fill" : "pause.circle",
                    helpText: viewModel.isPaused ? L10n.tr("action.resume") : L10n.tr("action.pause"),
                    tint: viewModel.isPaused ? .orange : .secondary,
                    accessibilityID: "pause-button"
                ) {
                    viewModel.togglePause()
                }

                HUDIconButton(
                    systemName: "sparkles",
                    helpText: L10n.tr("action.setup"),
                    tint: .secondary,
                    accessibilityID: "setup-button"
                ) {
                    viewModel.showSetupSheet = true
                }

                HUDIconButton(
                    systemName: "trash",
                    helpText: L10n.tr("action.clear"),
                    tint: viewModel.allItems.isEmpty ? .secondary.opacity(0.45) : .secondary,
                    accessibilityID: "clear-button"
                ) {
                    if !viewModel.allItems.isEmpty {
                        viewModel.showClearConfirmation = true
                    }
                }
                .disabled(viewModel.allItems.isEmpty)

                HUDIconButton(
                    systemName: "xmark",
                    helpText: L10n.tr("action.close"),
                    tint: .secondary,
                    accessibilityID: "close-button"
                ) {
                    viewModel.hideHUD()
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.isPaused ? Color.orange : Color.green)
                .frame(width: 6.5, height: 6.5)
            Text(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill((viewModel.isPaused ? Color.orange : Color.green).opacity(0.14))
        )
        .foregroundColor(viewModel.isPaused ? .orange : .green)
        .accessibilityIdentifier("status-badge")
        .accessibilityLabel(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
    }

    // MARK: - Search & Filter

    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField(L10n.tr("search.placeholder"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                    .accessibilityIdentifier("search-field")

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clear-search-button")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            // Hidden button for Cmd+F keyboard shortcut
            HStack(spacing: 6) {
                FilterTabButton(
                    title: "\(L10n.tr("filter.all")) (\(viewModel.allItems.count))",
                    isSelected: viewModel.selectedFilter == .all,
                    accessibilityID: "filter-all"
                ) {
                    viewModel.selectedFilter = .all
                }

                FilterTabButton(
                    title: "\(L10n.tr("filter.links")) (\(viewModel.urlCount))",
                    systemImage: "link",
                    isSelected: viewModel.selectedFilter == .url,
                    accessibilityID: "filter-url"
                ) {
                    viewModel.selectedFilter = .url
                }

                FilterTabButton(
                    title: "\(L10n.tr("filter.text")) (\(viewModel.textCount))",
                    systemImage: "doc.text",
                    isSelected: viewModel.selectedFilter == .text,
                    accessibilityID: "filter-text"
                ) {
                    viewModel.selectedFilter = .text
                }

                Spacer()

                // Keyboard shortcut triggers
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundColor(.orange)
            Text(L10n.tr("status.paused_banner"))
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.85))
            Spacer()
            Button(L10n.tr("action.resume")) {
                viewModel.togglePause()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(.orange)
            .accessibilityIdentifier("resume-banner-button")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.14))
        )
    }

    // MARK: - List

    private var clipsListSection: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(viewModel.filteredItems) { item in
                                ClipRowView(
                                    item: item,
                                    isSelected: viewModel.selectedItem?.id == item.id,
                                    isCopiedRecently: viewModel.copiedFeedbackID == item.id,
                                    onSelect: {
                                        viewModel.selectedItemID = item.id
                                    },
                                    onCopy: {
                                        viewModel.copyItem(item)
                                    },
                                    onCopyID: {
                                        viewModel.copyID(item)
                                    },
                                    onDelete: {
                                        viewModel.deleteItem(item)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.selectedItemID) { newID in
                        if let newID {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: viewModel.allItems.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text(viewModel.allItems.isEmpty ? L10n.tr("empty.title") : L10n.tr("empty.filtered_title"))
                .font(.system(size: 13.5, weight: .semibold))
            Text(viewModel.allItems.isEmpty ? L10n.tr("empty.subtitle") : L10n.tr("empty.filtered_subtitle"))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector Footer

    private var inspectorFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let item = viewModel.selectedItem {
                HStack(spacing: 8) {
                    Text(item.id)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .foregroundColor(.accentColor)

                    Text(L10n.tr("inspector.voice_prompt_label", item.voiceHint))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        viewModel.copyVoicePrompt(item)
                    } label: {
                        Label(L10n.tr("action.copy_prompt"), systemImage: "mic")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityIdentifier("copy-voice-prompt-button")
                }

                ScrollView {
                    Text(item.content)
                        .font(.system(size: 11.5, design: item.kind == .url ? .monospaced : .default))
                        .foregroundColor(.primary.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 54)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            } else {
                Text(L10n.tr("inspector.no_selection"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text(L10n.tr("shortcuts.hint"))
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Subviews

private struct HUDIconButton: View {
    let systemName: String
    let helpText: String
    let tint: Color
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct FilterTabButton: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5))
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(title)
    }
}

private struct ClipRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let isCopiedRecently: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onCopyID: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var badgeColor: Color {
        item.kind == .url ? .teal : .indigo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                // Stable Speakable ID Pill
                Text(item.id)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(badgeColor)
                    )
                    .accessibilityIdentifier("clip-id-\(item.id)")
                    .accessibilityLabel(item.id)

                // Kind / Domain badge
                HStack(spacing: 4) {
                    Image(systemName: item.kind == .url ? "link" : "doc.text")
                        .font(.system(size: 9.5, weight: .semibold))
                    if item.kind == .url, let domain = item.domain {
                        Text(domain)
                            .lineLimit(1)
                    } else {
                        Text("\(L10n.tr("kind.text")) · \(L10n.tr("inspector.chars_count", item.charCount))")
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(badgeColor.opacity(0.12))
                )

                Spacer()

                Text(RelativeDateTimeFormatter.localizedString(for: item.updatedAt, localeIdentifier: L10n.currentLocaleIdentifier()))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(item.preview)
                .font(.system(size: 12, design: item.kind == .url ? .monospaced : .default))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: onCopy) {
                    Label(
                        isCopiedRecently ? L10n.tr("action.copied") : L10n.tr("action.copy"),
                        systemImage: isCopiedRecently ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(isCopiedRecently ? .green : .accentColor)
                .accessibilityIdentifier("copy-button-\(item.id)")

                Button(action: onCopyID) {
                    Text(L10n.tr("action.copy_id"))
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityIdentifier("copy-id-button-\(item.id)")

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundColor(isHovering || isSelected ? .red.opacity(0.85) : .secondary.opacity(0.6))
                .help(L10n.tr("action.delete"))
                .accessibilityLabel("\(L10n.tr("action.delete")) \(item.id)")
                .accessibilityIdentifier("delete-button-\(item.id)")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip-row-\(item.id)")
    }
}

private extension RelativeDateTimeFormatter {
    @MainActor
    static let clipVoiceFormatters: [String: RelativeDateTimeFormatter] = {
        ["en", "ko"].reduce(into: [:]) { dict, id in
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .abbreviated
            fmt.locale = Locale(identifier: id)
            dict[id] = fmt
        }
    }()

    @MainActor
    static func localizedString(for date: Date, localeIdentifier: String) -> String {
        let fmt = clipVoiceFormatters[localeIdentifier] ?? clipVoiceFormatters["en"]!
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
