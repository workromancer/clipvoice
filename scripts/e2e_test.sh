#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_BIN="$ROOT_DIR/build/ClipVoice.app/Contents/MacOS/ClipVoice"
CLI_BIN="$ROOT_DIR/build/ClipVoice.app/Contents/MacOS/clipvoice-cli"
MCP_BIN="$ROOT_DIR/build/ClipVoice.app/Contents/MacOS/clipvoice-mcp"

if [[ ! -x "$APP_BIN" ]]; then
    "$ROOT_DIR/scripts/build.sh"
fi

TMP_DIR="$(mktemp -d /tmp/clipvoice-e2e.XXXXXX)"
STORE_PATH="$TMP_DIR/history.json"
PB_BACKUP="$TMP_DIR/pb_backup.plist"
APP_PID=""

swift "$ROOT_DIR/scripts/pb_snapshot.swift" save "$PB_BACKUP"

cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    swift "$ROOT_DIR/scripts/pb_snapshot.swift" restore "$PB_BACKUP" || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> [E2E 1/6] Launching ClipVoice.app in isolated temp store ($STORE_PATH)..."
"$APP_BIN" --store "$STORE_PATH" --hud-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!

# Verify live GUI HUD + pbcopy capture + reorder + pause/resume + filter + delete via macOS Accessibility
swift "$ROOT_DIR/scripts/ax_e2e.swift" full "$APP_PID"

sleep 0.2

echo "==> [E2E 2/6] Verifying clipvoice-cli list, get --raw exact bytes, and latest --raw..."
CLI_LIST="$("$CLI_BIN" list --store "$STORE_PATH" --json)"
echo "$CLI_LIST" | python3 -c '
import json, sys
items = json.load(sys.stdin)
ids = [x["id"] for x in items]
assert ids == ["clip-3", "clip-1"], f"Unexpected CLI IDs: {ids}"
assert items[1]["kind"] == "url" and items[1]["domain"] == "example.com"
print("CLI_LIST_VERIFIED:", ids)
'

# Verify --raw outputs exact bytes with NO extra trailing newline
python3 -c '
import subprocess, sys
cli = sys.argv[1]
store = sys.argv[2]
out = subprocess.check_output([cli, "get", "clip-1", "--raw", "--store", store])
expected = b"https://example.com/clipvoice/pr-42"
assert out == expected, f"Expected exact bytes {expected!r}, got {out!r}"
latest_url = subprocess.check_output([cli, "latest", "--kind", "url", "--raw", "--store", store])
assert latest_url == expected, f"Expected exact latest bytes {expected!r}, got {latest_url!r}"
print("CLI_RAW_EXACT_BYTES_VERIFIED:", len(out), "bytes, no added newline")
' "$CLI_BIN" "$STORE_PATH"

# Also test multiline + leading/trailing whitespace exact byte preservation via --raw
MULTILINE_STORE="$TMP_DIR/multiline.json"
python3 -c '
import json, subprocess, sys
cli = sys.argv[1]
store_path = sys.argv[2]
sample = "  line one\n\tline two  "
data = {
    "schemaVersion": 1,
    "nextSequence": 2,
    "isPaused": False,
    "maxItems": 50,
    "items": [{
        "id": "clip-1",
        "sequence": 1,
        "kind": "text",
        "content": sample,
        "createdAt": "2026-11-20T03:00:00Z",
        "updatedAt": "2026-11-20T03:00:00Z"
    }]
}
with open(store_path, "w", encoding="utf-8") as f:
    json.dump(data, f)
raw_get = subprocess.check_output([cli, "get", "clip-1", "--raw", "--store", store_path])
raw_latest = subprocess.check_output([cli, "latest", "--raw", "--store", store_path])
assert raw_get == sample.encode("utf-8"), f"Mismatch get --raw: {raw_get!r}"
assert raw_latest == sample.encode("utf-8"), f"Mismatch latest --raw: {raw_latest!r}"
print("CLI_RAW_MULTILINE_WHITESPACE_VERIFIED")
' "$CLI_BIN" "$MULTILINE_STORE"

echo "==> [E2E 3/6] Verifying clipvoice-mcp stdio JSON-RPC against isolated store..."
MCP_OUT="$(
    printf '%s\n%s\n%s\n%s\n%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_clips","arguments":{"limit":1e100}}}' \
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_clips","arguments":{}}}' \
        '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip one"}}}' \
    | "$MCP_BIN" --store "$STORE_PATH"
)"

echo "$MCP_OUT" | python3 -c '
import json, sys
lines = [json.loads(line) for line in sys.stdin.read().splitlines() if line.strip()]
assert len(lines) == 4, f"Expected 4 JSON-RPC responses, got {len(lines)}"
assert lines[0]["result"]["serverInfo"]["name"] == "clipvoice-mcp"
assert lines[1]["result"]["isError"] is True, "Expected 1e100 limit to return clean tool error"
list_payload = json.loads(lines[2]["result"]["content"][0]["text"])
assert [i["id"] for i in list_payload["items"]] == ["clip-3", "clip-1"]
clip1_payload = json.loads(lines[3]["result"]["content"][0]["text"])
assert clip1_payload["id"] == "clip-1"
assert clip1_payload["content"] == "https://example.com/clipvoice/pr-42"
print("MCP_STDIO_VERIFIED:", [i["id"] for i in list_payload["items"]], "->", clip1_payload["content"])
'

echo "==> [E2E 4/6] Verifying non-destructive install-skill behavior..."
SKILL_DIR="$TMP_DIR/arbitrary-user-dir"
mkdir -p "$SKILL_DIR"
printf 'keep me safe\n' > "$SKILL_DIR/user-notes.txt"
"$CLI_BIN" install-skill --target "$SKILL_DIR"
test -f "$SKILL_DIR/SKILL.md"
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"

# Simulate conflicting SKILL.md and ensure rejection without --backup
printf 'custom user skill\n' > "$SKILL_DIR/SKILL.md"
if "$CLI_BIN" install-skill --target "$SKILL_DIR" >/dev/null 2>&1; then
    echo "Expected install-skill to reject conflicting SKILL.md without --backup" >&2
    exit 1
fi
test "$(cat "$SKILL_DIR/SKILL.md")" = "custom user skill"
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"

# With --backup, old SKILL.md is backed up and unrelated files are preserved
"$CLI_BIN" install-skill --target "$SKILL_DIR" --backup
ls "$SKILL_DIR"/SKILL.md.bak.* >/dev/null
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"
echo "SKILL_INSTALL_NON_DESTRUCTIVE_VERIFIED"

# Terminate English session and verify Korean localized launch
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "==> [E2E 5/6] Verifying Korean localization launch (--locale ko)..."
"$APP_BIN" --store "$STORE_PATH" --hud-on-launch --no-hotkey --test-mode --locale ko >/dev/null 2>&1 &
APP_PID=$!
swift "$ROOT_DIR/scripts/ax_e2e.swift" ko "$APP_PID"

echo "==> [E2E 6/6] Restoring original pasteboard on exit..."
echo "==> ALL E2E CHECKS PASSED"
