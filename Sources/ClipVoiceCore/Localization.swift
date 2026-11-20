import Foundation

public enum L10n {
    nonisolated(unsafe) public static var overrideLocaleIdentifier: String?

    public static func currentLocaleIdentifier() -> String {
        if let overrideLocaleIdentifier, !overrideLocaleIdentifier.isEmpty {
            return normalizeLocale(overrideLocaleIdentifier)
        }
        if let preferred = Bundle.main.preferredLocalizations.first {
            return normalizeLocale(preferred)
        }
        if let preferredLang = Locale.preferredLanguages.first {
            return normalizeLocale(preferredLang)
        }
        return "en"
    }

    private static func normalizeLocale(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.hasPrefix("ko") { return "ko" }
        return "en"
    }

    public static func tr(_ key: String, _ args: CVarArg...) -> String {
        let localeID = currentLocaleIdentifier()
        var format: String?

        // 1. Standard macOS .app bundle (.lproj inside Contents/Resources)
        if let path = Bundle.main.path(forResource: localeID, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let localized = bundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if localized != "__MISSING__" {
                format = localized
            }
        }

        // 2. Fallback table for CLI/tests without .app bundle wrapper
        if format == nil {
            format = fallbackStrings[localeID]?[key] ?? fallbackStrings["en"]?[key]
        }

        let resolved = format ?? key
        if args.isEmpty {
            return resolved
        }
        return String(format: resolved, locale: Locale(identifier: localeID), arguments: args)
    }

    public static let requiredKeys: [String] = [
        "app.name",
        "app.tagline",
        "status.live",
        "status.paused",
        "status.paused_banner",
        "filter.all",
        "filter.links",
        "filter.text",
        "search.placeholder",
        "action.copy",
        "action.copied",
        "action.copy_id",
        "action.copy_prompt",
        "action.delete",
        "action.clear",
        "action.clear_confirm_title",
        "action.clear_confirm_message",
        "action.cancel",
        "action.pause",
        "action.resume",
        "action.pin",
        "action.unpin",
        "action.close",
        "action.setup",
        "action.show_hud",
        "action.hide_hud",
        "action.quit",
        "empty.title",
        "empty.subtitle",
        "empty.filtered_title",
        "empty.filtered_subtitle",
        "kind.url",
        "kind.text",
        "inspector.voice_prompt_label",
        "inspector.chars_count",
        "inspector.lines_count",
        "inspector.no_selection",
        "shortcuts.hint",
        "setup.title",
        "setup.subtitle",
        "setup.store_path",
        "setup.history_cap",
        "setup.global_hotkey",
        "setup.mcp_config_title",
        "setup.copy_mcp_config",
        "setup.skill_title",
        "setup.copy_skill_cmd",
        "setup.cli_title",
        "setup.privacy_note",
        "setup.done",
        "menu.recent_clips",
        "menu.no_recent",
        "menu.hotkey_label"
    ]

    private static let fallbackStrings: [String: [String: String]] = [
        "en": [
            "app.name": "ClipVoice",
            "app.tagline": "Speakable clipboard HUD for coding agents",
            "status.live": "Live",
            "status.paused": "Paused",
            "status.paused_banner": "Clipboard capture is paused. New copies are ignored until resumed.",
            "filter.all": "All",
            "filter.links": "Links",
            "filter.text": "Text",
            "search.placeholder": "Search ID, domain, or text...",
            "action.copy": "Copy",
            "action.copied": "Copied!",
            "action.copy_id": "Copy ID",
            "action.copy_prompt": "Copy Voice Prompt",
            "action.delete": "Delete",
            "action.clear": "Clear",
            "action.clear_confirm_title": "Clear clipboard history?",
            "action.clear_confirm_message": "This removes all captured entries from ClipVoice's local store.",
            "action.cancel": "Cancel",
            "action.pause": "Pause Capture",
            "action.resume": "Resume Capture",
            "action.pin": "Pin on Top",
            "action.unpin": "Unpin Window",
            "action.close": "Hide HUD",
            "action.setup": "Agent Setup",
            "action.show_hud": "Show Floating HUD",
            "action.hide_hud": "Hide Floating HUD",
            "action.quit": "Quit ClipVoice",
            "empty.title": "Clipboard history is empty",
            "empty.subtitle": "Copy any URL or text snippet (⌘C). ClipVoice assigns a stable speakable ID that never shifts when new items arrive.",
            "empty.filtered_title": "No matching clips",
            "empty.filtered_subtitle": "Try clearing your search query or switching tabs.",
            "kind.url": "LINK",
            "kind.text": "TEXT",
            "inspector.voice_prompt_label": "Say to agent: \"fetch %@\"",
            "inspector.chars_count": "%d chars",
            "inspector.lines_count": "%d lines",
            "inspector.no_selection": "Select a clip to inspect full content",
            "shortcuts.hint": "↑↓ Select · ⏎ Copy · ⌫ Delete · ⌘F Search · ⌥⌘V Toggle HUD",
            "setup.title": "Agent & Privacy Setup",
            "setup.subtitle": "Connect ClipVoice to your coding agent via local stdio MCP or CLI.",
            "setup.store_path": "Local Store Path",
            "setup.history_cap": "History Cap",
            "setup.global_hotkey": "Global Shortcut (⌥⌘V)",
            "setup.mcp_config_title": "Local Stdio MCP Config",
            "setup.copy_mcp_config": "Copy MCP JSON",
            "setup.skill_title": "Install Agent Skill",
            "setup.copy_skill_cmd": "Copy Skill Install Command",
            "setup.cli_title": "CLI Quick Commands",
            "setup.privacy_note": "100% local. Concealed/transient pasteboard items are excluded automatically, and clipboard links or text are never opened or executed automatically.",
            "setup.done": "Done",
            "menu.recent_clips": "Recent Clips",
            "menu.no_recent": "No clips captured yet",
            "menu.hotkey_label": "Shortcut: ⌥⌘V"
        ],
        "ko": [
            "app.name": "ClipVoice",
            "app.tagline": "코딩 에이전트를 위한 음성 대응 클립보드 HUD",
            "status.live": "수신 중",
            "status.paused": "일시정지",
            "status.paused_banner": "클립보드 캡처가 일시정지되었습니다. 재개할 때까지 새 항목을 저장하지 않습니다.",
            "filter.all": "전체",
            "filter.links": "링크",
            "filter.text": "텍스트",
            "search.placeholder": "ID, 도메인 또는 내용 검색...",
            "action.copy": "복사",
            "action.copied": "복사됨!",
            "action.copy_id": "ID 복사",
            "action.copy_prompt": "음성 프롬프트 복사",
            "action.delete": "삭제",
            "action.clear": "전체 삭제",
            "action.clear_confirm_title": "클립보드 기록을 모두 삭제할까요?",
            "action.clear_confirm_message": "ClipVoice 로컬 저장소의 모든 항목이 삭제됩니다.",
            "action.cancel": "취소",
            "action.pause": "캡처 일시정지",
            "action.resume": "캡처 재개",
            "action.pin": "항상 위에 고정",
            "action.unpin": "고정 해제",
            "action.close": "HUD 닫기",
            "action.setup": "에이전트 설정",
            "action.show_hud": "플로팅 HUD 열기",
            "action.hide_hud": "플로팅 HUD 숨기기",
            "action.quit": "ClipVoice 종료",
            "empty.title": "클립보드 기록이 비어 있습니다",
            "empty.subtitle": "URL이나 텍스트를 복사(⌘C)하세요. 새 항목이 추가되어도 바뀌지 않는 고정 음성 ID가 부여됩니다.",
            "empty.filtered_title": "일치하는 항목이 없습니다",
            "empty.filtered_subtitle": "검색어를 지우거나 필터 탭을 변경해 보세요.",
            "kind.url": "링크",
            "kind.text": "텍스트",
            "inspector.voice_prompt_label": "에이전트에게 말하기: \"%@ 가져와\"",
            "inspector.chars_count": "%d자",
            "inspector.lines_count": "%d줄",
            "inspector.no_selection": "전체 내용을 보려면 항목을 선택하세요",
            "shortcuts.hint": "↑↓ 선택 · ⏎ 복사 · ⌫ 삭제 · ⌘F 검색 · ⌥⌘V HUD 토글",
            "setup.title": "에이전트 및 개인정보 설정",
            "setup.subtitle": "로컬 stdio MCP 또는 CLI로 코딩 에이전트와 연결하세요.",
            "setup.store_path": "로컬 저장소 경로",
            "setup.history_cap": "최대 보관 개수",
            "setup.global_hotkey": "전역 단축키 (⌥⌘V)",
            "setup.mcp_config_title": "로컬 Stdio MCP 설정",
            "setup.copy_mcp_config": "MCP JSON 복사",
            "setup.skill_title": "에이전트 스킬 설치",
            "setup.copy_skill_cmd": "스킬 설치 명령 복사",
            "setup.cli_title": "CLI 빠른 명령어",
            "setup.privacy_note": "100% 로컬 동작. 보안/임시 클립보드 항목은 자동 제외되며, 복사된 링크나 텍스트를 자동으로 열거나 실행하지 않습니다.",
            "setup.done": "완료",
            "menu.recent_clips": "최근 클립",
            "menu.no_recent": "캡처된 항목 없음",
            "menu.hotkey_label": "단축키: ⌥⌘V"
        ]
    ]
}
