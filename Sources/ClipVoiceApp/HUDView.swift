import SwiftUI
import AppKit
import ClipVoiceCore

private enum HUDTheme {
    static let canvas = Color(red: 0.055, green: 0.059, blue: 0.075)         // #0E0F13 Linear deep charcoal
    static let surfaceElevated = Color(red: 0.082, green: 0.086, blue: 0.106)// #15161B
    static let rowHover = Color(red: 0.086, green: 0.094, blue: 0.118)       // #16181E
    static let rowSelected = Color(red: 0.114, green: 0.125, blue: 0.184)    // #1D202F Linear issue selection tint
    static let rowIncoming = Color(red: 0.110, green: 0.122, blue: 0.196)    // #1C1F32 subtle arrival tint
    static let tabActive = Color(red: 0.125, green: 0.133, blue: 0.165)      // #20222A
    static let searchBg = Color(red: 0.075, green: 0.080, blue: 0.100)       // #131419
    static let textPrimary = Color(red: 0.925, green: 0.933, blue: 0.953)    // #ECEEF3
    static let textSecondary = Color(red: 0.525, green: 0.549, blue: 0.600)  // #868C99
    static let textMuted = Color(red: 0.384, green: 0.408, blue: 0.459)      // #626875
    static let indigo = Color(red: 0.369, green: 0.416, blue: 0.824)         // #5E6AD2 Linear accent
    static let indigoSoft = Color(red: 0.549, green: 0.592, blue: 0.949)     // #8C97F2
    static let liveGreen = Color(red: 0.243, green: 0.812, blue: 0.557)      // #3ECF8E
    static let pausedAmber = Color(red: 0.898, green: 0.663, blue: 0.235)    // #E5A93C
    static let dangerRed = Color(red: 0.898, green: 0.380, blue: 0.380)      // #E56161
    static let hairline = Color.white.opacity(0.065)
    static let rowSeparator = Color.white.opacity(0.045)
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
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for rel in ["assets/clipvoice-icon-v2.png", "assets/clipvoice-icon.png"] {
            let candidate = cwd.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: candidate.path),
               let img = NSImage(contentsOf: candidate) {
                return img
            }
        }
        return nil
    }()
}

struct HUDView: View {
    @ObservedObject var viewModel: ClipVoiceViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mcpPulsePhase: Bool = false

    private let hudCornerRadius: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 365

            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                HUDTheme.canvas.opacity(0.95)

                VStack(spacing: 0) {
                    headerBar(isCompact: isCompact)
                        .frame(height: 38)
                        .padding(.horizontal, isCompact ? 10 : 14)

                    hairlineDivider

                    toolbarRow(isCompact: isCompact)
                        .padding(.horizontal, isCompact ? 10 : 14)
                        .padding(.vertical, 6)

                    hairlineDivider

                    if viewModel.isPaused {
                        pausedBanner(isCompact: isCompact)
                        hairlineDivider
                    }

                    clipsListSection(isCompact: isCompact)

                    hairlineDivider

                    bottomCommandBar(isCompact: isCompact)
                        .frame(height: 28)
                        .padding(.horizontal, isCompact ? 10 : 14)
                }

                if viewModel.showDisplayPopover {
                    overlayScrim { viewModel.showDisplayPopover = false }
                    VStack {
                        HStack {
                            Spacer()
                            DisplaySettingsPopover(viewModel: viewModel)
                                .shadow(color: Color.black.opacity(0.55), radius: 16, y: 6)
                        }
                        Spacer()
                    }
                    .padding(.top, 38)
                    .padding(.trailing, isCompact ? 8 : 12)
                    .transition(.opacity)
                }

                if viewModel.showDetailPopover, let item = viewModel.selectedItem {
                    let inspectorImageWidth = max(180, geo.size.width - 72)
                    let inspectorImageHeight = min(240, max(120, geo.size.height * 0.36))
                    overlayScrim { viewModel.showDetailPopover = false }
                    VStack {
                        Spacer()
                        ItemDetailInspectorOverlay(
                            item: item,
                            store: viewModel.store,
                            maxImageWidth: inspectorImageWidth,
                            maxImageHeight: inspectorImageHeight,
                            onCopy: { viewModel.copyItem(item) },
                            onCopyVoicePrompt: { viewModel.copyVoicePrompt(item) },
                            onClose: { viewModel.showDetailPopover = false }
                        )
                        .padding(12)
                        .shadow(color: Color.black.opacity(0.55), radius: 16, y: 4)
                    }
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .clipShape(RoundedRectangle(cornerRadius: hudCornerRadius, style: .continuous))
            .overlay(hudBorderOverlay)
            .padding(1)
        }
        .frame(minWidth: AppPreferencesStore.minDockWidth, minHeight: 400)
        .onChange(of: viewModel.mcpActivityActive) { active in
            updateMCPAnimation(active: active)
        }
        .onChange(of: viewModel.mcpActivityRevision) { _ in
            if viewModel.mcpActivityActive {
                updateMCPAnimation(active: true)
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

    private func overlayScrim(_ onTap: @escaping () -> Void) -> some View {
        Color.black.opacity(0.28)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    private func updateMCPAnimation(active: Bool) {
        if active && !reduceMotion {
            mcpPulsePhase = false
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                mcpPulsePhase = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                mcpPulsePhase = false
            }
        }
    }

    private var hudBorderOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: hudCornerRadius, style: .continuous)
        return ZStack {
            if viewModel.mcpActivityActive {
                shape
                    .strokeBorder(
                        HUDTheme.indigo.opacity(reduceMotion ? 0.85 : (mcpPulsePhase ? 0.95 : 0.40)),
                        lineWidth: 1.5
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("mcp-pulse-border")
                    .accessibilityLabel(viewModel.mcpActivityLabel ?? L10n.tr("mcp.activity.active"))
            } else {
                shape
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(HUDTheme.hairline)
            .frame(height: 1)
    }

    // MARK: - Header (38pt, compact Linear titlebar)

    private func headerBar(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            appLogoView(size: 18)

            Text(L10n.tr("app.name"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(HUDTheme.textPrimary)

            statusBadge(isCompact: isCompact)

            Spacer(minLength: 4)

            if let mcpLabel = viewModel.mcpActivityLabel {
                mcpActivityBadge(label: mcpLabel, isCompact: isCompact)
                    .transition(.opacity)
            }

            HStack(spacing: 2) {
                HeaderGlyphButton(
                    systemName: viewModel.isPaused ? "play.fill" : "pause",
                    helpText: viewModel.isPaused ? L10n.tr("action.resume") : L10n.tr("action.pause"),
                    tint: viewModel.isPaused ? HUDTheme.pausedAmber : HUDTheme.textSecondary,
                    isActive: viewModel.isPaused,
                    accessibilityID: "pause-button"
                ) {
                    viewModel.togglePause()
                }

                HeaderGlyphButton(
                    systemName: "slider.horizontal.3",
                    helpText: L10n.tr("display.title"),
                    tint: viewModel.showDisplayPopover ? HUDTheme.indigoSoft : HUDTheme.textSecondary,
                    isActive: viewModel.showDisplayPopover,
                    accessibilityID: "display-settings-button"
                ) {
                    viewModel.showDetailPopover = false
                    viewModel.showDisplayPopover.toggle()
                }

                HeaderGlyphButton(
                    systemName: "terminal",
                    helpText: L10n.tr("action.setup"),
                    tint: HUDTheme.textSecondary,
                    isActive: false,
                    accessibilityID: "setup-button"
                ) {
                    viewModel.showSetupSheet = true
                }

                HeaderGlyphButton(
                    systemName: "trash",
                    helpText: L10n.tr("action.clear"),
                    tint: viewModel.allItems.isEmpty ? HUDTheme.textMuted.opacity(0.4) : HUDTheme.textSecondary,
                    isActive: false,
                    accessibilityID: "clear-button"
                ) {
                    if !viewModel.allItems.isEmpty {
                        viewModel.showClearConfirmation = true
                    }
                }
                .disabled(viewModel.allItems.isEmpty)

                HeaderGlyphButton(
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

    private func appLogoView(size: CGFloat) -> some View {
        Group {
            if let nsImage = AppLogoLoader.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HUDTheme.indigoSoft)
                    .frame(width: size, height: size)
            }
        }
    }

    private func statusBadge(isCompact: Bool) -> some View {
        let color = viewModel.isPaused ? HUDTheme.pausedAmber : HUDTheme.liveGreen
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            if !isCompact || viewModel.isPaused {
                Text(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(viewModel.isPaused ? HUDTheme.pausedAmber : HUDTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("status-badge")
        .accessibilityLabel(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
        .accessibilityValue(viewModel.isPaused ? L10n.tr("status.paused") : L10n.tr("status.live"))
    }

    private func mcpActivityBadge(label: String, isCompact: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(HUDTheme.indigoSoft)
                .frame(width: 5, height: 5)
                .opacity(reduceMotion ? 1.0 : (mcpPulsePhase ? 1.0 : 0.45))
            Text(isCompact ? L10n.tr("mcp.activity.active") : label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 6.5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(HUDTheme.indigo.opacity(0.16)))
        .foregroundColor(HUDTheme.indigoSoft)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("mcp-activity-badge")
        .accessibilityLabel(label)
        .accessibilityValue(label)
    }

    // MARK: - Unified Filter & Search Toolbar

    private func toolbarRow(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 6 : 0) {
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    FilterTabButton(
                        title: "\(L10n.tr("filter.all")) \(viewModel.allItems.count)",
                        isSelected: viewModel.selectedFilter == .all,
                        compact: isCompact,
                        accessibilityID: "filter-all"
                    ) {
                        viewModel.selectedFilter = .all
                    }

                    FilterTabButton(
                        title: "\(L10n.tr("filter.links")) \(viewModel.urlCount)",
                        isSelected: viewModel.selectedFilter == .url,
                        compact: isCompact,
                        accessibilityID: "filter-url"
                    ) {
                        viewModel.selectedFilter = .url
                    }

                    FilterTabButton(
                        title: "\(L10n.tr("filter.text")) \(viewModel.textCount)",
                        isSelected: viewModel.selectedFilter == .text,
                        compact: isCompact,
                        accessibilityID: "filter-text"
                    ) {
                        viewModel.selectedFilter = .text
                    }

                    FilterTabButton(
                        title: "\(isCompact ? L10n.tr("filter.images_compact") : L10n.tr("filter.images")) \(viewModel.imageCount)",
                        isSelected: viewModel.selectedFilter == .image,
                        compact: isCompact,
                        accessibilityID: "filter-image"
                    ) {
                        viewModel.selectedFilter = .image
                    }
                }

                if !isCompact {
                    Spacer(minLength: 6)
                    searchFieldView(maxWidth: 165)
                } else {
                    Spacer(minLength: 0)
                }

                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            if isCompact {
                searchFieldView(maxWidth: nil)
            }
        }
    }

    private func searchFieldView(maxWidth: CGFloat?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundColor(HUDTheme.textMuted)

            TextField(L10n.tr("search.compact_placeholder"), text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(HUDTheme.textPrimary)
                .focused($searchFocused)
                .accessibilityIdentifier("search-field")

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(HUDTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clear-search-button")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: maxWidth)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(HUDTheme.searchBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(searchFocused ? HUDTheme.indigo.opacity(0.50) : Color.white.opacity(0.05), lineWidth: 0.75)
        )
    }

    private func pausedBanner(isCompact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 10.5))
                .foregroundColor(HUDTheme.pausedAmber)
            Text(isCompact ? L10n.tr("status.paused") : L10n.tr("status.paused_banner"))
                .font(.system(size: 10.5))
                .foregroundColor(HUDTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button(L10n.tr("action.resume")) {
                viewModel.togglePause()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(HUDTheme.pausedAmber)
            .accessibilityIdentifier("resume-banner-button")
        }
        .padding(.horizontal, isCompact ? 10 : 14)
        .padding(.vertical, 5)
        .background(HUDTheme.pausedAmber.opacity(0.08))
    }

    // MARK: - Flat Edge-to-Edge List

    private func clipsListSection(isCompact: Bool) -> some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.filteredItems) { item in
                                let isIncoming = viewModel.incomingHighlightID == item.id
                                let isPendingEntrance = isIncoming && viewModel.incomingEntrancePending && !reduceMotion

                                ClipRowView(
                                    item: item,
                                    store: viewModel.store,
                                    isSelected: viewModel.selectedItem?.id == item.id,
                                    isCopiedRecently: viewModel.copiedFeedbackID == item.id,
                                    isIncomingHighlighted: isIncoming,
                                    incomingIsNew: viewModel.incomingIsNew,
                                    isCompact: isCompact,
                                    onSelect: {
                                        viewModel.selectedItemID = item.id
                                    },
                                    onCopy: {
                                        viewModel.copyItem(item)
                                    },
                                    onCopyID: {
                                        viewModel.copyID(item)
                                    },
                                    onCopyVoicePrompt: {
                                        viewModel.copyVoicePrompt(item)
                                    },
                                    onInspect: {
                                        viewModel.selectedItemID = item.id
                                        viewModel.showDetailPopover = true
                                    },
                                    onDelete: {
                                        viewModel.deleteItem(item)
                                    }
                                )
                                .id(item.id)
                                .opacity(isPendingEntrance ? 0.12 : 1.0)
                                .offset(y: isPendingEntrance ? -10 : 0)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isPendingEntrance)
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedItemID) { newID in
                        if let newID {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: viewModel.incomingRevision) { _ in
                        if let targetID = viewModel.incomingHighlightID {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                                proxy.scrollTo(targetID, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 7) {
            Spacer()
            Image(systemName: viewModel.allItems.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(HUDTheme.textMuted)
            Text(viewModel.allItems.isEmpty ? L10n.tr("empty.title") : L10n.tr("empty.filtered_title"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(HUDTheme.textPrimary)
            Text(viewModel.allItems.isEmpty ? L10n.tr("empty.subtitle") : L10n.tr("empty.filtered_subtitle"))
                .font(.system(size: 10.5))
                .foregroundColor(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Slim Bottom Command Bar (28pt)

    private func bottomCommandBar(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            if let item = viewModel.selectedItem {
                Text(item.id)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(HUDTheme.textMuted)

                if !isCompact {
                    Text(L10n.tr("voice.cue", item.voiceHint))
                        .font(.system(size: 10.5))
                        .foregroundColor(HUDTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    viewModel.copyItem(item)
                } label: {
                    Text(viewModel.copiedFeedbackID == item.id ? L10n.tr("action.copied") : "\(L10n.tr("action.copy")) ⏎")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(viewModel.copiedFeedbackID == item.id ? HUDTheme.liveGreen : HUDTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("copy-selected-button")

                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(HUDTheme.textMuted)

                Button {
                    viewModel.showDisplayPopover = false
                    viewModel.showDetailPopover.toggle()
                } label: {
                    Text(L10n.tr("action.inspect"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(viewModel.showDetailPopover ? HUDTheme.indigoSoft : HUDTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("copy-voice-prompt-button")
            } else {
                Text(L10n.tr("inspector.no_selection"))
                    .font(.system(size: 10.5))
                    .foregroundColor(HUDTheme.textMuted)
                Spacer()
            }
        }
    }
}

// MARK: - Display & Window Popover

private struct DisplaySettingsPopover: View {
    @ObservedObject var viewModel: ClipVoiceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.tr("display.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(HUDTheme.textPrimary)

            HStack(spacing: 4) {
                PlacementPresetButton(
                    icon: "sidebar.left",
                    label: L10n.tr("placement.left"),
                    isSelected: viewModel.placementMode == .dockLeft,
                    accessibilityID: "dock-left-button"
                ) {
                    viewModel.setPlacementMode(.dockLeft)
                }

                PlacementPresetButton(
                    icon: "macwindow",
                    label: L10n.tr("placement.floating"),
                    isSelected: viewModel.placementMode == .floating,
                    accessibilityID: "dock-floating-button"
                ) {
                    viewModel.setPlacementMode(.floating)
                }

                PlacementPresetButton(
                    icon: "sidebar.right",
                    label: L10n.tr("placement.right"),
                    isSelected: viewModel.placementMode == .dockRight,
                    accessibilityID: "dock-right-button"
                ) {
                    viewModel.setPlacementMode(.dockRight)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(HUDTheme.canvas)
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("display.opacity"))
                        .font(.system(size: 11))
                        .foregroundColor(HUDTheme.textSecondary)
                    Spacer()
                    Text("\(Int((viewModel.opacity * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(HUDTheme.textPrimary)
                        .accessibilityIdentifier("opacity-value-label")
                }

                Slider(
                    value: Binding(
                        get: { viewModel.opacity },
                        set: { viewModel.setOpacity($0) }
                    ),
                    in: AppPreferencesStore.minOpacity...AppPreferencesStore.maxOpacity
                )
                .tint(HUDTheme.indigo)
                .accessibilityIdentifier("opacity-slider")

                HStack(spacing: 5) {
                    ForEach([0.50, 0.75, 0.96, 1.0], id: \.self) { preset in
                        let pct = Int(preset * 100)
                        let active = abs(viewModel.opacity - preset) < 0.02
                        Button("\(pct)%") {
                            viewModel.setOpacity(preset)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: active ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(active ? HUDTheme.indigoSoft : HUDTheme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(active ? HUDTheme.indigo.opacity(0.18) : Color.white.opacity(0.04))
                        )
                        .accessibilityIdentifier("opacity-preset-\(pct)")
                    }
                }
            }

            Rectangle().fill(HUDTheme.hairline).frame(height: 1)

            Toggle(isOn: Binding(
                get: { viewModel.isPinned },
                set: { viewModel.setPinned($0) }
            )) {
                Text(L10n.tr("display.always_on_top"))
                    .font(.system(size: 11.5))
                    .foregroundColor(HUDTheme.textPrimary)
            }
            .tint(HUDTheme.indigo)
            .accessibilityIdentifier("display-pin-toggle")

            Button {
                viewModel.resetDisplayDefaults()
            } label: {
                Text(L10n.tr("display.reset"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(HUDTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reset-display-button")
        }
        .padding(13)
        .frame(width: 242)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(HUDTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }
}

// MARK: - On-Demand Detail Inspector Overlay

private struct ItemDetailInspectorOverlay: View {
    let item: ClipItem
    let store: ClipStore
    let maxImageWidth: CGFloat
    let maxImageHeight: CGFloat
    let onCopy: () -> Void
    let onCopyVoicePrompt: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(item.id)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(HUDTheme.indigoSoft)
                if let domain = item.domain {
                    Text("· \(domain)")
                        .font(.system(size: 11))
                        .foregroundColor(HUDTheme.textSecondary)
                        .lineLimit(1)
                } else if let meta = item.image {
                    Text("· \(meta.dimensionsLabel) PNG · \(meta.formattedByteSize)")
                        .font(.system(size: 11))
                        .foregroundColor(HUDTheme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("· \(L10n.tr("inspector.chars_count", item.charCount))")
                        .font(.system(size: 11))
                        .foregroundColor(HUDTheme.textSecondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5))
                        .foregroundColor(HUDTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inspector-close-button")
            }

            if item.kind == .image, let meta = item.image {
                VStack(alignment: .leading, spacing: 6) {
                    ClipImageThumbnailView(
                        metadata: meta,
                        store: store,
                        maxWidth: maxImageWidth,
                        maxHeight: maxImageHeight,
                        accessibilityID: "inspector-image-preview"
                    )
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text("SHA-256: \(meta.sha256.prefix(16))… · \(meta.mimeType)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(HUDTheme.textMuted)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HUDTheme.searchBg)
                )
            } else {
                ScrollView {
                    Text(item.content)
                        .font(.system(size: 11.5, design: item.prefersMonospacedPreview ? .monospaced : .default))
                        .foregroundColor(HUDTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HUDTheme.searchBg)
                )
            }

            HStack(spacing: 8) {
                Button(L10n.tr("action.copy"), action: onCopy)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(HUDTheme.indigo)
                    .accessibilityIdentifier("inspector-copy-button")
                Button(L10n.tr("action.copy_prompt"), action: onCopyVoicePrompt)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(HUDTheme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
        )
    }
}

// MARK: - Subviews

private struct HeaderGlyphButton: View {
    let systemName: String
    let helpText: String
    let tint: Color
    let isActive: Bool
    let accessibilityID: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.09) : (isHovering ? Color.white.opacity(0.06) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct PlacementPresetButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10.5, weight: isSelected ? .medium : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? HUDTheme.tabActive : Color.clear)
            )
            .foregroundColor(isSelected ? HUDTheme.textPrimary : HUDTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct FilterTabButton: View {
    let title: String
    let isSelected: Bool
    var compact: Bool = false
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 10.5 : 11, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, compact ? 6.5 : 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? HUDTheme.tabActive : Color.clear)
                )
                .foregroundColor(isSelected ? HUDTheme.textPrimary : HUDTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(title)
    }
}

@MainActor
private enum ClipImageCache {
    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 80
        return c
    }()

    static func image(for metadata: ClipImageMetadata, store: ClipStore) -> NSImage? {
        let key = "\(store.fileURL.path)::\(metadata.sha256)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let pngData = store.imageAssets.readPNGData(for: metadata),
              let img = NSImage(data: pngData) else {
            return nil
        }
        cache.setObject(img, forKey: key)
        return img
    }
}

private struct TransparencyCheckerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 8
            let light = Color.white.opacity(0.06)
            let dark = Color.black.opacity(0.18)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let isEven = (row + col) % 2 == 0
                    ctx.fill(
                        Path(CGRect(x: x, y: y, width: tile, height: tile)),
                        with: .color(isEven ? light : dark)
                    )
                    x += tile
                    col += 1
                }
                y += tile
                row += 1
            }
        }
    }
}

private struct ClipImageThumbnailView: View {
    let metadata: ClipImageMetadata
    let store: ClipStore
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let accessibilityID: String

    private var aspectRatio: CGFloat {
        guard metadata.height > 0 else { return 1.0 }
        return CGFloat(metadata.width) / CGFloat(metadata.height)
    }

    private var displaySize: CGSize {
        let w = CGFloat(max(1, metadata.width))
        let h = CGFloat(max(1, metadata.height))
        let scale = min(maxWidth / w, maxHeight / h, 1.0)
        return CGSize(
            width: max(36, floor(w * scale)),
            height: max(32, floor(h * scale))
        )
    }

    var body: some View {
        let size = displaySize
        Group {
            if let nsImage = ClipImageCache.image(for: metadata, store: store) {
                ZStack {
                    TransparencyCheckerboard()
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                )
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "photo")
                    Text("\(metadata.dimensionsLabel) PNG")
                }
                .font(.system(size: 11))
                .foregroundColor(HUDTheme.textMuted)
                .padding(.vertical, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel("Image \(metadata.dimensionsLabel) PNG \(metadata.formattedByteSize)")
    }
}

private struct ClipRowView: View {
    let item: ClipItem
    let store: ClipStore
    let isSelected: Bool
    let isCopiedRecently: Bool
    let isIncomingHighlighted: Bool
    let incomingIsNew: Bool
    let isCompact: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onCopyID: () -> Void
    let onCopyVoicePrompt: () -> Void
    let onInspect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var kindIconName: String {
        switch item.kind {
        case .url: return "link"
        case .text: return "doc.text"
        case .image: return "photo"
        }
    }

    private var headerTitle: String {
        switch item.kind {
        case .url:
            return item.domain ?? "Link"
        case .image:
            if let meta = item.image {
                return "\(meta.dimensionsLabel) PNG · \(meta.formattedByteSize)"
            }
            return L10n.tr("kind.image")
        case .text:
            if item.lineCount > 1 {
                return "\(item.lineCount) lines · \(item.charCount)c"
            }
            return "\(item.charCount) chars"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? HUDTheme.indigo : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.id)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(isIncomingHighlighted || isSelected ? HUDTheme.indigoSoft : HUDTheme.textMuted)
                        .frame(minWidth: isCompact ? 42 : 46, alignment: .leading)
                        .accessibilityIdentifier("clip-id-\(item.id)")
                        .accessibilityLabel(item.id)

                    Image(systemName: kindIconName)
                        .font(.system(size: 10.5))
                        .foregroundColor(item.kind == .text ? HUDTheme.textMuted : HUDTheme.indigoSoft.opacity(0.85))

                    Text(headerTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(item.kind == .text ? HUDTheme.textSecondary : HUDTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isIncomingHighlighted {
                        Text(incomingIsNew ? L10n.tr("incoming.badge.new") : L10n.tr("incoming.badge.updated"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(HUDTheme.indigoSoft)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3.5).fill(HUDTheme.indigo.opacity(0.20)))
                            .accessibilityIdentifier("incoming-indicator-\(item.id)")
                            .accessibilityLabel(incomingIsNew ? L10n.tr("incoming.badge.new") : L10n.tr("incoming.badge.updated"))
                    }

                    Spacer(minLength: 6)

                    if isHovering || isSelected {
                        HStack(spacing: 6) {
                            RowActionGlyph(
                                systemName: isCopiedRecently ? "checkmark" : "doc.on.doc",
                                tint: isCopiedRecently ? HUDTheme.liveGreen : HUDTheme.textSecondary,
                                helpText: L10n.tr("action.copy"),
                                accessibilityID: "copy-button-\(item.id)",
                                action: onCopy
                            )
                            RowActionGlyph(
                                systemName: "number",
                                tint: HUDTheme.textSecondary,
                                helpText: L10n.tr("action.copy_id"),
                                accessibilityID: "copy-id-button-\(item.id)",
                                action: onCopyID
                            )
                            RowActionGlyph(
                                systemName: "trash",
                                tint: isHovering ? HUDTheme.dangerRed : HUDTheme.textMuted,
                                helpText: "\(L10n.tr("action.delete")) \(item.id)",
                                accessibilityID: "delete-button-\(item.id)",
                                action: onDelete
                            )
                        }
                    } else {
                        Text(RelativeDateTimeFormatter.localizedString(for: item.updatedAt, localeIdentifier: L10n.currentLocaleIdentifier()))
                            .font(.system(size: 10.5))
                            .foregroundColor(HUDTheme.textMuted)
                            .lineLimit(1)
                    }
                }

                Group {
                    switch item.kind {
                    case .image:
                        if let meta = item.image {
                            ClipImageThumbnailView(
                                metadata: meta,
                                store: store,
                                maxWidth: isCompact ? 200 : 290,
                                maxHeight: isCompact ? 88 : 112,
                                accessibilityID: "clip-image-thumb-\(item.id)"
                            )
                            .padding(.top, 1)
                        }
                    case .url:
                        Text(item.content.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Color(red: 0.77, green: 0.80, blue: 0.87))
                            .lineLimit(isCompact ? 2 : 3)
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    case .text:
                        Text(item.multilinePreview(maxCharacters: 600))
                            .font(.system(size: isCompact ? 11.5 : 12, design: item.prefersMonospacedPreview ? .monospaced : .default))
                            .foregroundColor(HUDTheme.textPrimary.opacity(0.94))
                            .lineLimit(isCompact ? 3 : 4)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, isCompact ? 49 : 53)
            }
            .padding(.leading, isCompact ? 8 : 12)
            .padding(.trailing, isCompact ? 10 : 14)
            .padding(.vertical, 8.5)
        }
        .background(
            isIncomingHighlighted
                ? HUDTheme.rowIncoming
                : (isSelected ? HUDTheme.rowSelected : (isHovering ? HUDTheme.rowHover : Color.clear))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HUDTheme.rowSeparator)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(L10n.tr("action.copy"), action: onCopy)
            Button(L10n.tr("action.copy_id"), action: onCopyID)
            Button(L10n.tr("action.copy_prompt"), action: onCopyVoicePrompt)
            Button(L10n.tr("action.inspect"), action: onInspect)
            Divider()
            Button(L10n.tr("action.delete"), role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip-row-\(item.id)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction {
            onSelect()
        }
        .accessibilityAction(named: L10n.tr("action.copy")) {
            onCopy()
        }
        .accessibilityAction(named: L10n.tr("action.delete")) {
            onDelete()
        }
    }
}

private struct RowActionGlyph: View {
    let systemName: String
    let tint: Color
    let helpText: String
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .foregroundColor(tint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityIdentifier(accessibilityID)
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
        let now = Date()
        if abs(now.timeIntervalSince(date)) < 2.0 || date > now {
            return localeIdentifier == "ko" ? "방금" : "now"
        }
        let fmt = clipVoiceFormatters[localeIdentifier] ?? clipVoiceFormatters["en"]!
        return fmt.localizedString(for: date, relativeTo: now)
    }
}
