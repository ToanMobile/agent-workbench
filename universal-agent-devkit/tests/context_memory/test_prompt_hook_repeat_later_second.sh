#!/usr/bin/env bash
# CI macOS đỏ oan test_prompt_hook_no_spawn (PR #1168, #1169): touch_session ghi touched_at theo giây, nên prompt bug lặp lại ở một
# giây sau lượt đầu đổi dòng → ghi sổ chờ (git show HEAD + tempfile) ngay trên đường hook. Ngoài đời lượt lặp luôn cách vài giây/phút,
# nên luồng "lặp không spawn" (#1127) chưa từng giữ được. Ca này lùi touched_at của dòng đã ghi 60 s (thay cho sleep) rồi chạy lượt lặp:
# cùng phiên, mới chạm gần đây ⇒ không ghi gì, không spawn, không nạp tempfile.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="${DEVKIT_DIR_UNDER_TEST:-$(cd "$(dirname "$0")/../.." && pwd)}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/p"; mkdir -p "$P/.agents"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t
echo '{"version": 1, "items": {}}' > "$P/.agents/regression_status.json"
git -C "$P" add -A && git -C "$P" commit -qm init
python3 -c 'import json; print(json.dumps({"prompt": "App bị crash khi mở màn hình bản đồ lần thứ hai", "session_id": "b", "transcript_path": "/nonexistent/claude-tr.jsonl"}))' > "$TMP/prompt.json"
export CLAUDE_PROJECT_DIR="$P" STALE_RERUN=0 RED_PROOF=0
python3 -I -B "$DEVKIT_DIR/scripts/context/enrich_context.py" --hook < "$TMP/prompt.json" > "$TMP/first" 2>&1
# Lùi touched_at 60 s ở mọi nơi dòng có thể nằm (sổ chờ trong git dir, file track): lượt lặp rơi vào "một giây khác" một cách tất định.
python3 - "$P" <<'PY' || { echo "✖ lượt đầu không ghi dòng bug nào có touched_at: $(head -c 300 "$TMP/first")"; exit 1; }
import json, pathlib, sys, time
p = pathlib.Path(sys.argv[1]); old = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 60)); n = 0
for f in list((p / ".git").rglob("*.json")) + [p / ".agents/regression_status.json"]:
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    rows = d.get("rows") or d.get("items") if isinstance(d, dict) else None
    for r in (rows or {}).values():
        if isinstance(r, dict) and r.get("kind") == "bug" and r.get("touched_at"):
            r["touched_at"] = old; n += 1
            f.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
sys.exit(0 if n else 1)
PY
PROMPT_DEDUPE=0 python3 -I -B - "$DEVKIT_DIR/scripts/context/enrich_context.py" "$TMP/prompt.json" <<'PY'
import io, runpy, sys
enrich, prompt = sys.argv[1], sys.argv[2]
spawns = []
sys.addaudithook(lambda ev, args: spawns.append(f"{ev} {str(args)[:120]}") if ev in (
    "subprocess.Popen", "os.posix_spawn", "os.exec", "os.system", "os.fork", "os.spawn") else None)
sys.stdin = io.TextIOWrapper(io.BytesIO(open(prompt, "rb").read()), encoding="utf-8")
sys.argv = [enrich, "--hook"]
out, real = io.StringIO(), sys.stdout
sys.stdout = out
try:
    runpy.run_path(enrich, run_name="__main__")
except SystemExit:
    pass
sys.stdout = real
fails = 0
if "Bug đã ghi vào checklist" not in out.getvalue():
    fails += 1; print("✖ the bug path did not run:", out.getvalue()[:600])
if spawns:
    fails += 1; print(f"✖ repeat bug prompt 60 s later spawned {len(spawns)} process(es):"); [print("   ", s) for s in spawns]
else:
    print("✔ repeat bug prompt 60 s later: no subprocess")
if "tempfile" in sys.modules:
    fails += 1; print("✖ repeat bug prompt 60 s later imported tempfile (rewrote the row)")
else:
    print("✔ repeat bug prompt 60 s later: row not rewritten (no tempfile)")
sys.exit(1 if fails else 0)
PY
