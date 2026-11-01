#!/usr/bin/env bash
# test_parity_check.sh — #773 (01/11): 5 repo app lệch kit (verify_commands còn --full --auto-approve-tests dù #741/#764 đã cấm, bản sao
# super-board cũ, hook kit chưa đăng ký) mà không lệnh nào báo; mỗi chỗ chỉ lộ ra khi PR kẹt ở merge gate.
# Luật: `agent-kit parity <repo>` liệt kê mọi loại lệch, exit 1 khi lệch, exit 0 khi repo vừa cài khớp kit; --fix bỏ cờ cấm khỏi
# verify_commands mà giữ phần còn lại của file; `agent-kit init` (install.sh) chạy parity --fix ở bước cuối, exit của install không đổi.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en

DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/parity-check.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/proj"
mkdir -p "$P/.claude/super-board/configs" && (cd "$P" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo x > a && git add a && git commit -qm init)
CFG="$P/.claude/super-board/configs/proj.json"
# Config như Idle/Goods trước #773: cờ cấm trong verify_commands, khoá khác phải giữ nguyên từng byte
printf '{\n  "base_branch": "main",\n  "verify_commands": [\n    "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief --auto-approve-tests",\n    "npm test"\n  ],\n  "note": "giữ nguyên"\n}\n' > "$CFG"

# 1) init chạy parity --fix ở bước cuối: cờ cấm bị bỏ, phần còn lại của file giữ nguyên, exit của install vẫn 0
bash "$DEVKIT/bin/install.sh" -t "$P" -y -p universal --agents=claude --no-githooks -m symlink > "$TMP/i1.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "init exit 0" || { fail "init exit $rc"; tail -5 "$TMP/i1.out"; }
want='{\n  "base_branch": "main",\n  "verify_commands": [\n    "python3 .agents/devkit/bin/post-fix-gate.py --run-tests --brief",\n    "npm test"\n  ],\n  "note": "giữ nguyên"\n}\n'
[ "$(cat "$CFG")" = "$(printf "$want")" ] && ok "init bỏ --full/--auto-approve-tests khỏi verify_commands, phần còn lại giữ nguyên" \
  || fail "config sau init: $(cat "$CFG")"
grep -q "^fixed: .claude/super-board/configs/proj.json — removed --auto-approve-tests, --full" "$TMP/i1.out" \
  && ok "init in dòng fixed cho config" || fail "init không in dòng fixed: $(grep -m3 -E 'parity|fixed' "$TMP/i1.out")"
grep -q "^parity: " "$TMP/i1.out" && ok "init in tổng parity ở cuối" || fail "init không chạy parity: $(tail -3 "$TMP/i1.out")"

# 2) repo vừa cài, không config super-board (không có gì để so bản sao): khớp kit, exit 0
mv "$P/.claude/super-board" "$TMP/sb-aside"
bash "$DEVKIT/bin/install.sh" -t "$P" -y --no-githooks -m symlink > "$TMP/i2.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "^parity: .* matches the kit" "$TMP/i2.out" && ok "re-init khi repo khớp kit: exit 0, in 'matches the kit'" \
  || fail "re-init khi khớp kit: exit $rc, $(tail -3 "$TMP/i2.out")"
# Hook kit viết khác mà installer vẫn coi là một (merge_json._hook_key + matcher giao nhau): matcher đảo thứ tự, lời echo riêng
python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
for e in s["hooks"]["PreToolUse"]:
    if e.get("matcher") == "Read|Edit":
        e["matcher"] = "Edit|Read"
for e in s["hooks"]["SessionStart"]:
    for h in e["hooks"]:
        if "session_context.sh" in h["command"]:
            h["command"] = 'bash -c \'if [ -f "$1" ]; then exec bash "$1"; fi; echo "loi rieng cua repo"\' _ "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/session_context.sh"'
json.dump(s, open(p, "w"), indent=2)
PY
python3 "$DEVKIT/bin/parity_check.py" "$P" > "$TMP/p0.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "matches the kit" "$TMP/p0.out" && ok "repo vừa cài khớp kit (kể cả hook viết khác cùng script): exit 0" \
  || fail "repo vừa cài bị báo lệch (exit $rc): $(head -5 "$TMP/p0.out")"
mv "$TMP/sb-aside" "$P/.claude/super-board"

# 2b) settings.json không có hook DevKit (chỉ cài Gemini) không bị so; thư mục con nêu rõ được kiểm nguyên, không leo lên gốc git
Q="$TMP/mono"; mkdir -p "$Q/.claude" "$Q/app/.claude/super-board/configs" && (cd "$Q" && git init -q)
echo '{"permissions":{"allow":[]}}' > "$Q/.claude/settings.json"
python3 "$DEVKIT/bin/parity_check.py" "$Q" > "$TMP/q0.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "settings.json không có hook DevKit: không báo hook-missing" || fail "báo sai repo không cài Claude: $(head -3 "$TMP/q0.out")"
echo '{"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --full"]}' > "$Q/app/.claude/super-board/configs/app.json"
python3 "$DEVKIT/bin/parity_check.py" "$Q/app" > "$TMP/q1.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "^forbidden-flag: .claude/super-board/configs/app.json" "$TMP/q1.out" \
  && ok "thư mục con nêu rõ: kiểm config của chính nó" || fail "thư mục con: exit $rc, $(head -3 "$TMP/q1.out")"

# 3) mỗi loại lệch đều được báo, exit 1; gọi qua agent-kit parity
printf '{"base_branch":"main","verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --force-full"]}\n' > "$CFG"
ln -s "$TMP/nowhere" "$P/.claude/hooks/ghost.sh"
mkdir -p "$TMP/old/universal-agent-devkit/bin" && ln -s "$TMP/old/universal-agent-devkit" "$P/.agents/old-kit"
rm -f "$P/.claude/hooks/block-dangerous-git.sh" && echo '# ban cu' > "$P/.claude/hooks/block-dangerous-git.sh"
python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
for e in s["hooks"]["PreToolUse"]:
    e["hooks"] = [h for h in e["hooks"] if "instincts_file_context.sh" not in h.get("command", "")]
s["hooks"].setdefault("Stop", []).append({"hooks": [{"type": "command", "command": 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/gone.sh"'}]})
json.dump(s, open(p, "w"), indent=2)
PY
bash "$DEVKIT/bin/agent-kit" parity "$P" > "$TMP/p1.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "lệch: exit 1" || fail "lệch mà exit $rc"
for want in "forbidden-flag: .claude/super-board/configs/proj.json — verify_commands has --force-full" \
            "broken-link: .claude/hooks/ghost.sh" \
            "foreign-kit-link: .agents/old-kit" \
            "copied-hook: .claude/hooks/block-dangerous-git.sh — a regular file, not a link to the kit (content differs" \
            "hook-missing: .claude/settings.json — PreToolUse Read|Edit:" \
            "hook-dangling: .claude/settings.json — Stop runs .claude/hooks/gone.sh"; do
  grep -qF "$want" "$TMP/p1.out" && ok "báo: ${want%% —*}" || fail "không báo: $want"
done
if [ -f "$DEVKIT/../.claude/bin/super-board-drift.py" ]; then
  grep -q "^super-board-drift: .claude/bin/super-board-merge-gate.sh — missing" "$TMP/p1.out" \
    && ok "báo: super-board-drift (bản sao super-board thiếu)" || fail "không báo bản sao super-board thiếu: $(grep -m2 drift "$TMP/p1.out")"
fi

# 4) --fix chỉ sửa cờ cấm; chỗ lệch khác vẫn được báo, exit vẫn 1
python3 "$DEVKIT/bin/parity_check.py" "$P" --fix > "$TMP/p2.out" 2>&1; rc=$?
grep -q -- "--force-full" "$CFG" && fail "--fix không bỏ --force-full: $(cat "$CFG")" || ok "--fix bỏ --force-full"
! grep -q "^forbidden-flag" "$TMP/p2.out" && grep -q "^broken-link" "$TMP/p2.out" && [ "$rc" -eq 1 ] \
  && ok "--fix: chỗ lệch khác vẫn báo, exit 1" || fail "--fix: exit $rc, $(head -3 "$TMP/p2.out")"

# 5) kiểm --fix với cờ trong ngoặc (DROP_RE chỉ bỏ cờ sau khoảng trắng): mong đợi dòng forbidden-flag, không dòng fixed, file y nguyên;
#    lệnh không gọi post-fix-gate.py (git fsck --full) mong đợi không bị báo — hai assert ngay dưới
printf '{"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py \\"--full\\"","git fsck --full"]}\n' > "$CFG"
cp "$CFG" "$TMP/cfg.before"
python3 "$DEVKIT/bin/parity_check.py" "$P" --fix > "$TMP/p3.out" 2>&1
! grep -q "^fixed:" "$TMP/p3.out" && grep -qF 'forbidden-flag: .claude/super-board/configs/proj.json — verify_commands has --full: python3' "$TMP/p3.out" \
  && cmp -s "$CFG" "$TMP/cfg.before" && ok "cờ trong ngoặc: báo, không ghi 'fixed', file giữ nguyên" || fail "cờ trong ngoặc: $(grep -E '^(fixed|forbidden)' "$TMP/p3.out")"
! grep -q "git fsck" "$TMP/p3.out" && ok "lệnh không gọi post-fix-gate.py (git fsck --full) không bị báo" || fail "báo nhầm git fsck --full"

# 5b) review Claude #773: lệnh gate nối lệnh khác bằng && / ;. Cờ của lệnh sau (git fsck --full, npm … -- --full) không phải cờ gate:
#     --fix chỉ bỏ cờ cấm trong phần đối số của post-fix-gate.py; --full-name là token khác, không báo
printf '{"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full && git fsck --full","python3 .agents/devkit/bin/post-fix-gate.py --brief; npm run e2e -- --full","python3 .agents/devkit/bin/post-fix-gate.py --full-name x"]}\n' > "$CFG"
want='{"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --run-tests && git fsck --full","python3 .agents/devkit/bin/post-fix-gate.py --brief; npm run e2e -- --full","python3 .agents/devkit/bin/post-fix-gate.py --full-name x"]}'
python3 "$DEVKIT/bin/parity_check.py" "$P" --fix > "$TMP/p4.out" 2>&1
[ "$(cat "$CFG")" = "$want" ] && ok "lệnh nối: --fix chỉ bỏ --full của post-fix-gate.py, giữ git fsck --full / npm -- --full / --full-name" \
  || fail "lệnh nối: config sau --fix: $(cat "$CFG")"
grep -qF "fixed: .claude/super-board/configs/proj.json — removed --full" "$TMP/p4.out" && ! grep -q "^forbidden-flag" "$TMP/p4.out" \
  && ok "lệnh nối: in fixed, không còn forbidden-flag" || fail "lệnh nối: $(grep -E '^(fixed|forbidden)' "$TMP/p4.out")"

# 6) worktree liên kết (worktree.py add, lane, scratch merge gate đều chạy install.sh): chỉ báo, không sửa config đã track
printf '{"verify_commands":["python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full"]}\n' > "$CFG"
git -C "$P" add .claude/super-board/configs/proj.json && git -C "$P" commit -qm cfg
git -C "$P" worktree add -q "$TMP/wt"
bash "$DEVKIT/bin/install.sh" -t "$TMP/wt" -y --no-githooks -m symlink > "$TMP/i3.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -z "$(git -C "$TMP/wt" status --porcelain -- .claude/super-board)" ] && grep -q "^forbidden-flag: .claude/super-board/configs/proj.json" "$TMP/i3.out" \
  && ok "init vào worktree liên kết: chỉ báo cờ cấm, config đã track không bẩn" \
  || fail "worktree liên kết: exit $rc, $(git -C "$TMP/wt" status --porcelain -- .claude/super-board) $(grep -m2 -E '^(fixed|forbidden)' "$TMP/i3.out")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_parity_check: PASS"; exit 0; } || { echo "test_parity_check: FAIL ($FAILS)"; exit 1; }
