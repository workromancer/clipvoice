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
PREFS_SUITE="dev.workromancer.clipvoice.e2e.$$"
AX_BIN="$TMP_DIR/ax_e2e"
APP_PID=""

swiftc "$ROOT_DIR/scripts/ax_e2e.swift" -o "$AX_BIN"
swift "$ROOT_DIR/scripts/pb_snapshot.swift" save "$PB_BACKUP"

cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    defaults delete "$PREFS_SUITE" >/dev/null 2>&1 || true
    swift "$ROOT_DIR/scripts/pb_snapshot.swift" restore "$PB_BACKUP" || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Seed a stale pre-launch .mcp-activity file to verify startup ignores stale activity.
cat > "${STORE_PATH}.mcp-activity" <<'EOF'
{"eventID":"stale-prelaunch-id","operation":"get_clip","timestamp":1577836800}
EOF

echo "==> [E2E 1/8] Launching ClipVoice.app in isolated temp store ($STORE_PATH) & isolated prefs ($PREFS_SUITE)..."
"$APP_BIN" --store "$STORE_PATH" --prefs-suite "$PREFS_SUITE" --hud-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!

"$AX_BIN" check-no-mcp "$APP_PID"
"$AX_BIN" full "$APP_PID"

sleep 0.2

echo "==> [E2E 2/8] Verifying CLI write --stdin -> NSPasteboard exact bytes -> running HUD incoming animation (no read pulse) & repeated write dedupe..."
WRITE_PAYLOAD=$'  func clipVoiceWrite() {\n\treturn 123\n  }  '
WRITE_JSON="$(printf '%s' "$WRITE_PAYLOAD" | "$CLI_BIN" write --stdin --json --store "$STORE_PATH")"
echo "$WRITE_JSON" | python3 -c '
import json, sys
out = json.load(sys.stdin)
assert out["id"] == "clip-4", f"Expected clip-4, got {out}"
assert out["status"] == "created"
print("CLI_WRITE_JSON_VERIFIED:", out["id"], out["status"])
'

# Readback exact bytes directly from system NSPasteboard
python3 -c '
import subprocess
pb = subprocess.check_output(["pbpaste"])
expected = b"  func clipVoiceWrite() {\n\treturn 123\n  }  "
assert pb == expected, f"Pasteboard mismatch: {pb!r} != {expected!r}"
print("NSPasteboard_READBACK_EXACT_BYTES_VERIFIED:", len(pb), "bytes")
'

"$AX_BIN" wait-incoming "$APP_PID" clip-4
"$AX_BIN" check-no-mcp "$APP_PID"

# Verify repeated identical CLI write deduplicates to clip-4 (no duplicate clip-5!) and re-animates
sleep 0.6
WRITE_REPEAT_JSON="$(printf '%s' "$WRITE_PAYLOAD" | "$CLI_BIN" write --stdin --json --store "$STORE_PATH")"
echo "$WRITE_REPEAT_JSON" | python3 -c '
import json, sys
out = json.load(sys.stdin)
assert out["id"] == "clip-4", f"Expected deduped clip-4, got {out}"
assert out["status"] == "updated"
print("CLI_WRITE_DEDUPE_VERIFIED:", out["id"], out["status"])
'
"$AX_BIN" wait-incoming "$APP_PID" clip-4
"$AX_BIN" check-no-mcp "$APP_PID"

# Verify MCP write_clip writes exact whitespace-wrapped URL bytes to store + pasteboard, animates card entrance even when a search/filter hides other items, and triggers NO MCP read pulse
"$AX_BIN" press-id "$APP_PID" filter-text
sleep 0.2
MCP_WRITE_OUT="$(
    printf '%s\n%s\n%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"write_clip","arguments":{"content":"  https://example.com/wrapped  "}}}' \
    | "$MCP_BIN" --store "$STORE_PATH"
)"
echo "$MCP_WRITE_OUT" | python3 -c '
import json, subprocess, sys
lines = [json.loads(line) for line in sys.stdin.read().splitlines() if line.strip()]
payload = json.loads(lines[1]["result"]["content"][0]["text"])
assert payload["id"] == "clip-5" and payload["kind"] == "url" and payload["status"] == "created"
pb = subprocess.check_output(["pbpaste"])
assert pb == b"  https://example.com/wrapped  ", f"Unexpected pasteboard bytes: {pb!r}"
print("MCP_WRITE_CLIP_VERIFIED:", payload["id"], "exact wrapped URL bytes")
'
"$AX_BIN" wait-incoming "$APP_PID" clip-5
"$AX_BIN" check-no-mcp "$APP_PID"

# Confirm history still has exact items [clip-5, clip-4, clip-3, clip-1] (no lost history, no duplicates!)
CLI_LIST="$("$CLI_BIN" list --store "$STORE_PATH" --json)"
echo "$CLI_LIST" | python3 -c '
import json, sys
items = json.load(sys.stdin)
ids = [x["id"] for x in items]
assert ids == ["clip-5", "clip-4", "clip-3", "clip-1"], f"Unexpected CLI IDs: {ids}"
print("NO_LOST_HISTORY_VERIFIED:", ids)
'

echo "==> [E2E 3/8] Verifying exact --raw bytes on get & latest..."
python3 -c '
import subprocess, sys
cli = sys.argv[1]
store = sys.argv[2]
raw_url = subprocess.check_output([cli, "get", "clip-1", "--raw", "--store", store])
assert raw_url == b"https://example.com/clipvoice/pr-42", f"Unexpected get --raw: {raw_url!r}"
raw_latest = subprocess.check_output([cli, "latest", "--raw", "--store", store])
assert raw_latest == b"  https://example.com/wrapped  ", f"Unexpected latest --raw: {raw_latest!r}"
raw_clip4 = subprocess.check_output([cli, "get", "clip-4", "--raw", "--store", store])
assert raw_clip4 == b"  func clipVoiceWrite() {\n\treturn 123\n  }  ", f"Unexpected clip-4 --raw: {raw_clip4!r}"
print("CLI_RAW_EXACT_BYTES_VERIFIED")
' "$CLI_BIN" "$STORE_PATH"

echo "==> [E2E 4/8] Verifying Left/Right dock presets, free slim resize, floating restore & opacity relaunch persistence..."
"$AX_BIN" placement-and-resize "$APP_PID"
"$AX_BIN" opacity-set-75 "$APP_PID"

# Quit and relaunch with SAME isolated prefs suite to prove persistence across launches
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

"$APP_BIN" --store "$STORE_PATH" --prefs-suite "$PREFS_SUITE" --hud-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!
"$AX_BIN" verify-opacity-75 "$APP_PID"

echo "==> [E2E 5/8] Verifying metadata MCP calls do NOT trigger pulse, then data MCP calls trigger + extend + expire (~5s)..."
printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
| "$MCP_BIN" --store "$STORE_PATH" >/dev/null
sleep 0.5
"$AX_BIN" check-no-mcp "$APP_PID"

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
assert len(lines) == 4
assert lines[1]["result"]["isError"] is True
list_payload = json.loads(lines[2]["result"]["content"][0]["text"])
assert [i["id"] for i in list_payload["items"]] == ["clip-5", "clip-4", "clip-3", "clip-1"]
clip1_payload = json.loads(lines[3]["result"]["content"][0]["text"])
assert clip1_payload["id"] == "clip-1"
assert clip1_payload["content"] == "https://example.com/clipvoice/pr-42"
print("MCP_STDIO_VERIFIED:", [i["id"] for i in list_payload["items"]], "->", clip1_payload["content"])
'

"$AX_BIN" wait-mcp-on "$APP_PID" 3.0
sleep 3.0
printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":10,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"list_clips","arguments":{}}}' \
| "$CLI_BIN" mcp --store "$STORE_PATH" >/dev/null
sleep 2.6
"$AX_BIN" wait-mcp-on "$APP_PID" 1.5
echo "MCP_PULSE_EXTEND_VERIFIED"
"$AX_BIN" wait-mcp-off "$APP_PID" 5.0

echo "==> [E2E 6/8] Verifying non-destructive install-skill behavior..."
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
"$CLI_BIN" install-skill --target "$SKILL_DIR" --backup
ls "$SKILL_DIR"/SKILL.md.bak.* >/dev/null
test "$(cat "$SKILL_DIR/user-notes.txt")" = "keep me safe"
echo "SKILL_INSTALL_NON_DESTRUCTIVE_VERIFIED"

kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "==> [E2E 7/8] Verifying Korean localization launch (--locale ko) & hidden HUD respect..."
"$APP_BIN" --store "$STORE_PATH" --prefs-suite "$PREFS_SUITE" --hud-on-launch --no-hotkey --test-mode --locale ko >/dev/null 2>&1 &
APP_PID=$!
"$AX_BIN" ko "$APP_PID"
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "==> [E2E 7b] Verifying end-to-end clipboard image capture (TIFF -> PNG), MCP image block, HUD copy -> NSPasteboard, CLI write-image & orphan cleanup..."
IMG_E2E_STORE="$TMP_DIR/images-e2e.json"
IMG_TIFF="$TMP_DIR/fixture.tiff"
IMG_PNG="$TMP_DIR/fixture.png"
IMG_EXPORT="$TMP_DIR/exported.png"

swift - "$IMG_TIFF" "$IMG_PNG" <<'SWIFT'
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let tiffURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pngURL = URL(fileURLWithPath: CommandLine.arguments[2])

func makeImage(width: Int, height: Int) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 0.18, green: 0.45, blue: 0.88, alpha: 0.85)
    ctx.fill(CGRect(x: 8, y: 8, width: width - 16, height: height - 16))
    return ctx.makeImage()!
}

let img = makeImage(width: 140, height: 90)
let tiffData = NSMutableData()
let tiffDest = CGImageDestinationCreateWithData(tiffData, UTType.tiff.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(tiffDest, img, nil)
CGImageDestinationFinalize(tiffDest)
try (tiffData as Data).write(to: tiffURL)

let png2 = makeImage(width: 110, height: 150)
let pngData = NSMutableData()
let pngDest = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(pngDest, png2, nil)
CGImageDestinationFinalize(pngDest)
try (pngData as Data).write(to: pngURL)
SWIFT

"$APP_BIN" --store "$IMG_E2E_STORE" --prefs-suite "$PREFS_SUITE" --hud-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!
sleep 0.8

# Copy synthetic TIFF onto live NSPasteboard -> app captures clip-1
swift - "$IMG_TIFF" <<'SWIFT'
import AppKit
import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let pb = NSPasteboard.general
pb.clearContents()
pb.setData(data, forType: .tiff)
SWIFT

"$AX_BIN" verify-image-copy "$APP_PID" clip-1

# Verify MCP get_clip returns standard base64 PNG image content block + triggers read pulse
MCP_IMG_OUT="$(
    printf '%s\n%s\n%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_clip","arguments":{"id":"clip-1"}}}' \
    | "$MCP_BIN" --store "$IMG_E2E_STORE"
)"
echo "$MCP_IMG_OUT" | python3 -c '
import base64, json, sys
lines = [json.loads(line) for line in sys.stdin.read().splitlines() if line.strip()]
blocks = lines[1]["result"]["content"]
assert blocks[0]["type"] == "text" and blocks[1]["type"] == "image"
assert blocks[1]["mimeType"] == "image/png"
raw = base64.b64decode(blocks[1]["data"])
assert raw.startswith(b"\x89PNG\r\n\x1a\n")
print("MCP_IMAGE_BLOCK_VERIFIED:", len(raw), "PNG bytes")
'
"$AX_BIN" wait-mcp-on "$APP_PID" 3.0
"$AX_BIN" wait-mcp-off "$APP_PID" 6.0

# Verify CLI write-image --file -> incoming indicator (no read pulse), repeat dedupe, and --output-file export
WRITE_IMG_JSON="$("$CLI_BIN" write-image --file "$IMG_PNG" --json --store "$IMG_E2E_STORE")"
echo "$WRITE_IMG_JSON" | python3 -c '
import json, sys
out = json.load(sys.stdin)
assert out["id"] == "clip-2" and out["kind"] == "image" and out["status"] == "created"
assert out["image"]["width"] == 110 and out["image"]["height"] == 150
print("CLI_WRITE_IMAGE_VERIFIED:", out["id"], out["image"]["width"], "x", out["image"]["height"])
'
"$AX_BIN" wait-incoming "$APP_PID" clip-2
"$AX_BIN" check-no-mcp "$APP_PID"

REPEAT_IMG_JSON="$("$CLI_BIN" write-image --file "$IMG_PNG" --json --store "$IMG_E2E_STORE")"
echo "$REPEAT_IMG_JSON" | python3 -c '
import json, sys
out = json.load(sys.stdin)
assert out["id"] == "clip-2" and out["status"] == "updated"
print("CLI_WRITE_IMAGE_DEDUPE_VERIFIED:", out["id"])
'
"$CLI_BIN" get clip-2 --output-file "$IMG_EXPORT" --json --store "$IMG_E2E_STORE" >/dev/null
python3 -c '
import glob, os, sys
with open(sys.argv[1], "rb") as f:
    assert f.read().startswith(b"\x89PNG\r\n\x1a\n")
tmp_dir = sys.argv[2]
assert not os.path.exists(os.path.join(tmp_dir, "images")), "Shared parent images/ dir should not be used"
img_dirs = glob.glob(os.path.join(tmp_dir, "images-images-e2e-*"))
assert len(img_dirs) == 1 and os.path.isdir(img_dirs[0]), f"Expected namespaced asset dir, got {img_dirs}"
print("CLI_IMAGE_EXPORT_AND_NAMESPACE_VERIFIED:", os.path.basename(img_dirs[0]))
' "$IMG_EXPORT" "$TMP_DIR"

kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

"$APP_BIN" --store "$STORE_PATH" --prefs-suite "$PREFS_SUITE" --hidden-on-launch --no-hotkey --test-mode --locale en >/dev/null 2>&1 &
APP_PID=$!
printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_latest_clip","arguments":{}}}' \
| "$MCP_BIN" --store "$STORE_PATH" >/dev/null
"$AX_BIN" check-hidden "$APP_PID"

echo "==> [E2E 8/8] Restoring original pasteboard & cleaning test prefs on exit..."
echo "==> ALL E2E CHECKS PASSED"
