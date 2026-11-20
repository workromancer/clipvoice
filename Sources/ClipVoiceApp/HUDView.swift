import SwiftUI
import AppKit
import ClipVoiceCore

private enum HUDTheme {
    static let canvasTop = Color(red: 0.043, green: 0.063, blue: 0.114)      // #0B101D
    static let canvasBottom = Color(red: 0.028, green: 0.043, blue: 0.082)   // #070B15
    static let cardSurface = Color(red: 0.075, green: 0.106, blue: 0.180)    // #131B2E
    static let cardSelected = Color(red: 0.090, green: 0.141, blue: 0.243)   // #17243E
    static let insetSurface = Color(red: 0.035, green: 0.051, blue: 0.094)   // #090D18
    static let textPrimary = Color(red: 0.945, green: 0.961, blue: 0.976)    // #F1F5F9
    static let textSecondary = Color(red: 0.541, green: 0.608, blue: 0.722)  // #8A9BB8
    static let cyan = Color(red: 0.133, green: 0.827, blue: 0.933)           // #22D3EE
    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)         // #8B5CF6
    static let liveGreen = Color(red: 0.204, green: 0.827, blue: 0.600)      // #34D399
    static let pausedAmber = Color(red: 0.984, green: 0.749, blue: 0.141)    // #FBBF24
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = NSAppearance(named: .darkAqua)
    }
}

private enum AppLogoLoader {
    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let devURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/clipvoice-icon.png")
        if FileManager.default.fileExists(atPath: devURL.path),
           let img = NSImage(contentsOf: devURL) {
            return img
        }
        return nil
    }()
}

struct HUDView: View {
    @ObservedObject var viewModel: ClipVoiceViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseBreath: Bool = false

    private let hudCornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [HUDTheme.canvasTop.opacity(0.94), HUDTheme.canvasBottom.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 14)
                    .padding(.top, 13)
                    .padding(.bottom, 10)

                hairlineDivider

                searchAndFilterBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                if viewModel.isPaused {
                    pausedBanner
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }

                clipsListSection

                hairlineDivider

                inspectorFooter
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: hudCornerRadius, style: .continuous))
        .overlay(hudBorderOverlay)
        .padding(viewModel.mcpActivityActive ? 3 : 1)
        .frame(minWidth: 440, minHeight: 480)
        .onChange(of: viewModel.mcpActivityActive) { active in
            updatePulseAnimation(active: active)
        }
        .onChange(of: viewModel.mcpActivityRevision) { _ in
            if viewModel.mcpActivityActive {
                updatePulseAnimation(active: true)
            }
        }
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

    private func updatePulseAnimation(active: Bool) {
        if active && !reduceMotion {
            pulseBreath = false
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulseBreath = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulseBreath = false
            }
        }
    }

    private var hudBorderOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: hudCornerRadius, style: .continuous)
        return ZStack {
            if viewModel.mcpActivityActive {
                // Soft outer luminous aura
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [HUDTheme.cyan, HUDTheme.violet, HUDTheme.cyan],
                            startPoint: pulseBreath ? .topLeading : .bottomTrailing,
                            endPoint: pulseBreath ? .bottomTrailing : .topLeading
                        ),
                        lineWidth: 4.5
                    )
                    .blur(radius: 4)
                    .opacity(reduceMotion ? 0.65 : (pulseBreath ? 0.82 : 0.30))

                // Crisp luminous perimeter ring
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [HUDTheme.cyan, HUDTheme.violet, HUDTheme.cyan],
                            startPoint: pulseBreath ? .topLeading : .topTrailing,
                            endPoint: pulseBreath ? .bottomTrailing : .bottomLeading
                        ),
                        lineWidth: 2.4
                    )
                    .opacity(reduceMotion ? 0.95 : (pulseBreath ? 1.0 : 0.68))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("mcp-pulse-border")
                    .accessibilityLabel(viewModel.mcpActivityLabel ?? L10n.tr("mcp.activity.active"))
            } else {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [HUDTheme.cyan.opacity(0.28), HUDTheme.violet.opacity(0.18), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, HUDTheme.cyan.opacity(0.22), HUDTheme.violet.opacity(0.18), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            appLogoView

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(L10n.tr("app.name"))
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(HUDTheme.textPrimary)

                    statusBadge

                    Text(ClipVoiceVersion.current)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(HUDTheme.textSecondary.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }

                Text(L10n.tr("app.tagline"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(HUDTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                HUDIconButton(
                    systemName: viewModel.isPinned ? "pin.fill" : "pin",
                    helpText: viewModel.isPinned ? L10n.tr("action.unpin") : L10n.tr("action.pin"),
                    tint: viewModel.isPinned ? HUDTheme.cyan : HUDTheme.textSecondary,
                    isActive: viewModel.isPinned,
                    accessibilityID: "pin-button"
                ) {
                    viewModel.togglePin()
                }

                HUDIconButton(
                    systemName: viewModel.isPaused ? "play.circle.fill" : "pause.circle",
                    helpText: viewModel.isPaused ? L10n.tr("action.resume") : L10n.tr("action.pause"),
                    tint: viewModel.isPaused ? HUDTheme.pausedAmber : HUDTheme.textSecondary,
                    isActive: viewModel.isPaused,
                    accessibilityID: "pause-button"
                ) {
                    viewModel.togglePause()
                }

                HUDIconButton(
                    systemName: "slider.horizontal.3",
                    helpText: L10n.tr("action.setup"),
                    tint: HUDTheme.textSecondary,
                    isActive: false,
                    accessibilityID: "setup-button"
                ) {
                    viewModel.showSetupSheet = true
                }

                HUDIconButton(
                    systemName: "trash",
                    helpText: L10n.tr("action.clear"),
                    tint: viewModel.allItems.isEmpty ? HUDTheme.textSecondary.opacity(0.35) : HUDTheme.textSecondary,
                    isActive: false,
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
                    tint: HUDTheme.textSecondary,
                    isActive: false,
                    accessibilityID: "close-button"
                ) {
                    viewModel.hideHUD()
                }
            }
        }
    }

    private var appLogoView: some View {
        Group {
            if let nsImage = AppLogoLoader.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(HUDTheme.cyan.opacity(0.45), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [HUDTheme.cyan.opacity(0.85), HUDTheme.violet.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var statusBadge: some View {
        let color = viewModel.isPaused ? HUDTheme.pausedAmber : HUDTheme.liveGreen
        return HStack(spacing: 4.5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.75), radius: 3)
            Text(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
        .foregroundColor(color)
        .accessibilityIdentifier("status-badge")
        .accessibilityLabel(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
    }

    // MARK: - Search & Filter

    private var searchAndFilterBar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(HUDTheme.cyan.opacity(0.8))

                TextField(L10n.tr("search.placeholder"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(HUDTheme.textPrimary)
                    .focused($searchFocused)
                    .accessibilityIdentifier("search-field")

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(HUDTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clear-search-button")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(HUDTheme.insetSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(searchFocused ? HUDTheme.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )

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

                Spacer(minLength: 6)

                if let mcpLabel = viewModel.mcpActivityLabel {
                    mcpActivityBadge(label: mcpLabel)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }

                // Keyboard shortcut triggers
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private func mcpActivityBadge(label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(HUDTheme.cyan)
                .frame(width: 6, height: 6)
                .opacity(reduceMotion ? 1.0 : (pulseBreath ? 1.0 : 0.45))
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [HUDTheme.cyan.opacity(0.18), HUDTheme.violet.opacity(0.18)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [HUDTheme.cyan.opacity(0.75), HUDTheme.violet.opacity(0.70)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .foregroundColor(HUDTheme.cyan)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("mcp-activity-badge")
        .accessibilityLabel(label)
        .accessibilityValue(label)
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundColor(HUDTheme.pausedAmber)
            Text(L10n.tr("status.paused_banner"))
                .font(.system(size: 11))
                .foregroundColor(HUDTheme.textPrimary.opacity(0.9))
            Spacer()
            Button(L10n.tr("action.resume")) {
                viewModel.togglePause()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(HUDTheme.pausedAmber)
            .accessibilityIdentifier("resume-banner-button")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HUDTheme.pausedAmber.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HUDTheme.pausedAmber.opacity(0.32), lineWidth: 1)
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
                        LazyVStack(spacing: 8) {
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
            Image(systemName: viewModel.allItems.isEmpty ? "waveform.and.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(HUDTheme.cyan.opacity(0.65))
            Text(viewModel.allItems.isEmpty ? L10n.tr("empty.title") : L10n.tr("empty.filtered_title"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(HUDTheme.textPrimary)
            Text(viewModel.allItems.isEmpty ? L10n.tr("empty.subtitle") : L10n.tr("empty.filtered_subtitle"))
                .font(.system(size: 11.5))
                .foregroundColor(HUDTheme.textSecondary)
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
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HUDTheme.cyan.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(HUDTheme.cyan.opacity(0.40), lineWidth: 0.75))
                        .foregroundColor(HUDTheme.cyan)

                    Text(L10n.tr("inspector.voice_prompt_label", item.voiceHint))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(HUDTheme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        viewModel.copyVoicePrompt(item)
                    } label: {
                        Label(L10n.tr("action.copy_prompt"), systemImage: "mic")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(HUDTheme.cyan)
                    .accessibilityIdentifier("copy-voice-prompt-button")
                }

                ScrollView {
                    Text(item.content)
                        .font(.system(size: 11.5, design: item.kind == .url ? .monospaced : .default))
                        .foregroundColor(HUDTheme.textPrimary.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 54)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(HUDTheme.insetSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
            } else {
                Text(L10n.tr("inspector.no_selection"))
                    .font(.system(size: 11))
                    .foregroundColor(HUDTheme.textSecondary)
            }

            Text(L10n.tr("shortcuts.hint"))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(HUDTheme.textSecondary.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Subviews

private struct HUDIconButton: View {
    let systemName: String
    let helpText: String
    let tint: Color
    let isActive: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 27, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? tint.opacity(0.14) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isActive ? tint.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 0.75)
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
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(isSelected ? HUDTheme.cyan.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? HUDTheme.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .foregroundColor(isSelected ? HUDTheme.cyan : HUDTheme.textSecondary)
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

    private var badgeAccent: Color {
        item.kind == .url ? HUDTheme.cyan : HUDTheme.violet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                // Stable Speakable ID Pill
                Text(item.id)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(item.kind == .url ? Color(red: 0.02, green: 0.12, blue: 0.16) : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(badgeAccent)
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
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(badgeAccent)
                .padding(.horizontal, 7.5)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(badgeAccent.opacity(0.14)))
                .overlay(Capsule().strokeBorder(badgeAccent.opacity(0.28), lineWidth: 0.75))

                Spacer()

                Text(RelativeDateTimeFormatter.localizedString(for: item.updatedAt, localeIdentifier: L10n.currentLocaleIdentifier()))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(HUDTheme.textSecondary.opacity(0.85))
            }

            Text(item.preview)
                .font(.system(size: 12, design: item.kind == .url ? .monospaced : .default))
                .foregroundColor(HUDTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: onCopy) {
                    Label(
                        isCopiedRecently ? L10n.tr("action.copied") : L10n.tr("action.copy"),
                        systemImage: isCopiedRecently ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(isCopiedRecently ? HUDTheme.liveGreen : HUDTheme.cyan)
                .accessibilityIdentifier("copy-button-\(item.id)")

                Button(action: onCopyID) {
                    Text(L10n.tr("action.copy_id"))
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(HUDTheme.textSecondary)
                .accessibilityIdentifier("copy-id-button-\(item.id)")

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundColor(isHovering || isSelected ? Color(red: 0.97, green: 0.44, blue: 0.44) : HUDTheme.textSecondary.opacity(0.6))
                .help(L10n.tr("action.delete"))
                .accessibilityLabel("\(L10n.tr("action.delete")) \(item.id)")
                .accessibilityIdentifier("delete-button-\(item.id)")
            }
        }
        .padding(10.5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? HUDTheme.cardSelected : HUDTheme.cardSurface.opacity(isHovering ? 0.96 : 0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? HUDTheme.cyan.opacity(0.65)
                        : Color.white.opacity(isHovering ? 0.14 : 0.07),
                    lineWidth: isSelected ? 1.25 : 1
                )
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
