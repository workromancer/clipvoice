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

# Seed a stale pre-launch .mcp-activity file to verify startup ignores stale activity.
cat > "${STORE_PATH}.mcp-activity" <<'EOF'
{"eventID":"stale-prelaunch-id","operation":"get_clip","timestamp":"2020-01-01T00:00:00Z"}
EOF

echo "==> [E2E 1/7] Launching ClipVoice.app in isolated temp store ($STORE_PATH)..."
"$APP_BIN" --store "$STORE_PATH" --hud-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!

# Verify no stale MCP pulse on startup
swift "$ROOT_DIR/scripts/ax_e2e.swift" check-no-mcp "$APP_PID"

# Verify live GUI HUD + pbcopy capture + reorder + pause/resume + filter + delete via macOS Accessibility
swift "$ROOT_DIR/scripts/ax_e2e.swift" full "$APP_PID"

sleep 0.2

echo "==> [E2E 2/7] Verifying clipvoice-cli list, get --raw exact bytes, and latest --raw..."
CLI_LIST="$("$CLI_BIN" list --store "$STORE_PATH" --json)"
echo "$CLI_LIST" | python3 -c '
import json, sys
items = json.load(sys.stdin)
ids = [x["id"] for x in items]
assert ids == ["clip-3", "clip-1"], f"Unexpected CLI IDs: {ids}"
assert items[1]["kind"] == "url" and items[1]["domain"] == "example.com"
print("CLI_LIST_VERIFIED:", ids)
'

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

echo "==> [E2E 3/7] Verifying metadata MCP calls do NOT trigger pulse, then data MCP calls trigger + extend + expire (~5s)..."
# Metadata calls must NOT trigger pulse
printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
| "$MCP_BIN" --store "$STORE_PATH" >/dev/null
sleep 0.5
swift "$ROOT_DIR/scripts/ax_e2e.swift" check-no-mcp "$APP_PID"

# Actual data read via standalone clipvoice-mcp triggers pulse border + accessible badge
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
assert lines[1]["result"]["isError"] is True
list_payload = json.loads(lines[2]["result"]["content"][0]["text"])
assert [i["id"] for i in list_payload["items"]] == ["clip-3", "clip-1"]
clip1_payload = json.loads(lines[3]["result"]["content"][0]["text"])
assert clip1_payload["id"] == "clip-1"
assert clip1_payload["content"] == "https://example.com/clipvoice/pr-42"
print("MCP_STDIO_VERIFIED:", [i["id"] for i in list_payload["items"]], "->", clip1_payload["content"])
'

swift "$ROOT_DIR/scripts/ax_e2e.swift" wait-mcp-on "$APP_PID" 3.0

# Wait 3.0s, then invoke `clipvoice-cli mcp` to extend the ~5s pulse past t=5s
sleep 3.0
printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":10,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"list_clips","arguments":{}}}' \
| "$CLI_BIN" mcp --store "$STORE_PATH" >/dev/null

# Wait 2.6s (now 5.6s since first call, only 2.6s since repeat call) -> MUST STILL BE ACTIVE
sleep 2.6
swift "$ROOT_DIR/scripts/ax_e2e.swift" wait-mcp-on "$APP_PID" 1.5
echo "MCP_PULSE_EXTEND_VERIFIED"

# Wait for the extended 5s window to expire cleanly
swift "$ROOT_DIR/scripts/ax_e2e.swift" wait-mcp-off "$APP_PID" 5.0

echo "==> [E2E 4/7] Verifying non-destructive install-skill behavior..."
SKILL_DIR="$TMP_DIR/arbitrary-user-dir"
mkdir -p "$SKILL_DIR"
printf 'keep me safe\n' > "$SKILL_DIR/user-notes.txt"
"$CLI_BIN" install-skill --target "$SKILL_DIR"
test -f "$SKILL_DIR/SKILL.md"
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"

printf 'custom user skill\n' > "$SKILL_DIR/SKILL.md"
if "$CLI_BIN" install-skill --target "$SKILL_DIR" >/dev/null 2>&1; then
    echo "Expected install-skill to reject conflicting SKILL.md without --backup" >&2
    exit 1
fi
test "$(cat "$SKILL_DIR/SKILL.md")" = "custom user skill"
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"

"$CLI_BIN" install-skill --target "$SKILL_DIR" --backup
ls "$SKILL_DIR"/SKILL.md.bak.* >/dev/null
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"
echo "SKILL_INSTALL_NON_DESTRUCTIVE_VERIFIED"

# Terminate English session and verify Korean localization launch + hidden HUD behavior
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "==> [E2E 5/7] Verifying Korean localization launch (--locale ko)..."
"$APP_BIN" --store "$STORE_PATH" --hud-on-launch --no-hotkey --test-mode --locale ko >/dev/null 2>&1 &
APP_PID=$!
swift "$ROOT_DIR/scripts/ax_e2e.swift" ko "$APP_PID"
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "==> [E2E 6/7] Verifying hidden HUD does NOT auto-open or steal focus on MCP access..."
"$APP_BIN" --store "$STORE_PATH" --hidden-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!
printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_latest_clip","arguments":{}}}' \
| "$MCP_BIN" --store "$STORE_PATH" >/dev/null
swift "$ROOT_DIR/scripts/ax_e2e.swift" check-hidden "$APP_PID"

echo "==> [E2E 7/7] Restoring original pasteboard on exit..."
echo "==> ALL E2E CHECKS PASSED"
