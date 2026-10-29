#!/usr/bin/env bash
# Test hồi quy (#644, INSTINCT-070): kit thêm skill + lệnh mới (gate-full) sau khi repo đã cài ⇒ repo phải tự có link, không cần `agent-kit init`.
#   a. checkout chính: relink_check --links-only (SessionStart) tạo .claude/commands/gate-full.md + .agents/skills/gate-full, trỏ vào kit;
#   b. linked worktree (git worktree add thường): relink_check --links-only cũng tạo hai link đó (trước đây bỏ qua mọi worktree), ngoài git;
#      file lệnh người dùng tự viết giữ nguyên;
#   c. không bao giờ trỏ sang checkout khác: kit nằm trong checkout CHÍNH của cùng repo thì relink cho worktree không tạo link vào đó;
#      kit của chính worktree thì có;
#   d. health: link chết trong .claude/commands ⇒ FAIL (fatal), thông báo nêu tên link.
# Mọi thứ trong thư mục tạm. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
RELINK="$DEVKIT_DIR/scripts/governance/relink_check.py"
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
unset DEVKIT_RELINK
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
into() { case "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")" in "$2"/*) return 0 ;; esac
         case "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1")" in "$2"/*) true ;; *) false ;; esac; }
real() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

[ -f "$DEVKIT_DIR/skills/gate-full/SKILL.md" ] && [ -e "$DEVKIT_DIR/commands/gate-full.md" ] \
  || { echo "✖ kit không có skill/lệnh gate-full (fixture)"; exit 1; }

# ── a. checkout chính ──
P="$TMP/p"; mkdir -p "$P" && cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false
echo x > a && git add a && git commit -qm init
bash "$DEVKIT_DIR/bin/install.sh" -t "$P" -a claude -p backend -y >/dev/null 2>&1
git add -A && git commit -qm "devkit install" >/dev/null 2>&1   # phần tracked của bản cài (link nằm ngoài git: .git/info/exclude)
[ -L .claude/commands/gate-full.md ] && [ -L .agents/skills/gate-full ] || { fail "fixture: install không link gate-full"; exit 1; }
rm -f .claude/commands/gate-full.md .agents/skills/gate-full   # kit cũ không có gate-full: link chưa từng được tạo
python3 "$RELINK" "$P" --quiet --links-only
[ -L .claude/commands/gate-full.md ] && [ -L .agents/skills/gate-full ] && [ -f .agents/skills/gate-full/SKILL.md ] \
  && [ "$(real .agents/skills/gate-full)" = "$DEVKIT_DIR/skills/gate-full" ] \
  && ok "a. checkout chính: SessionStart relink tạo link lệnh + skill mới, trỏ vào kit" \
  || fail "a. checkout chính: link gate-full không được tạo / sai đích ($(ls -la .claude/commands/gate-full.md .agents/skills/gate-full 2>&1 | tr '\n' ' '))"

# ── b. linked worktree ──
W="$TMP/w"; git -C "$P" worktree add -q --detach "$W" HEAD 2>/dev/null || { fail "fixture: worktree add"; exit 1; }
mkdir -p "$W/.claude/commands" && printf '# lệnh tự viết\n' > "$W/.claude/commands/adr.md"   # file người dùng tự viết
before="$(git -C "$W" status --porcelain)"
python3 "$RELINK" "$W" --quiet --links-only
[ -L "$W/.claude/commands/gate-full.md" ] && [ -f "$W/.claude/commands/gate-full.md" ] && [ -L "$W/.agents/skills/gate-full" ] \
  && [ "$(real "$W/.agents/skills/gate-full")" = "$DEVKIT_DIR/skills/gate-full" ] \
  && ok "b. linked worktree: relink tạo link lệnh + skill mới, trỏ vào kit" \
  || fail "b. linked worktree: thiếu link gate-full ($(ls -la "$W/.claude/commands/gate-full.md" "$W/.agents/skills/gate-full" 2>&1 | tr '\n' ' '))"
[ ! -L "$W/.claude/commands/adr.md" ] && grep -q "tự viết" "$W/.claude/commands/adr.md" && ok "b. file lệnh người dùng tự viết giữ nguyên" \
  || fail "b. relink đè file lệnh người dùng"
[ "$(git -C "$W" status --porcelain)" = "$before" ] && ok "b. link mới ngoài git (status worktree không đổi)" \
  || fail "b. link mới hiện trong git status: $(git -C "$W" status --porcelain | head -3 | tr '\n' ' ')"

# ── c. không trỏ sang checkout khác ──
R="$TMP/r"; mkdir -p "$R/kit/scripts/governance" "$R/kit/commands" "$R/kit/skills/neo" "$R/kit/profiles" "$R/kit/rules" "$R/.agents/skills" "$R/.claude/commands"
cp "$RELINK" "$R/kit/scripts/governance/relink_check.py"
printf '# neo\n' > "$R/kit/skills/neo/SKILL.md"; ln -s ../skills/neo/SKILL.md "$R/kit/commands/neo.md"; : > "$R/kit/rules/essentials.md"
printf '{"profile":"backend"}\n' > "$R/.agents/active-profile.json"; printf '{"hooks":{}}\n' > "$R/.claude/settings.json"
: > "$R/.agents/skills/.keep"; : > "$R/.claude/commands/.keep"; : > "$R/kit/profiles/.keep"   # git không giữ thư mục rỗng
( cd "$R" && git init -q -b main . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
W2="$TMP/w2"; git -C "$R" worktree add -q --detach "$W2" HEAD 2>/dev/null || { fail "fixture: worktree add (c)"; exit 1; }
python3 "$R/kit/scripts/governance/relink_check.py" "$W2" --quiet --links-only   # kit của checkout CHÍNH chạy cho worktree
[ ! -e "$W2/.claude/commands/neo.md" ] && [ ! -L "$W2/.claude/commands/neo.md" ] && [ ! -L "$W2/.agents/skills/neo" ] \
  && ok "c. kit thuộc checkout khác của cùng repo: không link worktree sang đó" \
  || fail "c. worktree bị link sang kit của checkout chính: $(ls -la "$W2/.claude/commands/neo.md" "$W2/.agents/skills/neo" 2>&1 | tr '\n' ' ')"
python3 "$W2/kit/scripts/governance/relink_check.py" "$W2" --quiet --links-only   # kit của chính worktree
[ -L "$W2/.agents/skills/neo" ] && [ "$(real "$W2/.agents/skills/neo")" = "$(real "$W2/kit/skills/neo")" ] \
  && [ -f "$W2/.claude/commands/neo.md" ] && [ "$(real "$W2/.claude/commands/neo.md")" = "$(real "$W2/kit/skills/neo/SKILL.md")" ] \
  && ok "c. kit của chính worktree: link trỏ vào kit trong worktree" \
  || fail "c. kit của chính worktree không được link: $(ls -la "$W2/.claude/commands/neo.md" "$W2/.agents/skills/neo" 2>&1 | tr '\n' ' ')"

# ── d. health: link chết ⇒ FAIL có tên link ──
ln -s "$TMP/khong-co/ghost.md" "$P/.claude/commands/ghost.md"
out="$(python3 "$DEVKIT_DIR/bin/agent-health.py" -t "$P" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"; rc=$?
res="$(printf '%s\n' "$out" | grep -E 'Result:' | head -1)"
case "$res" in *FAIL*) printf '%s\n' "$out" | grep -q "ghost.md" && ok "d. health: link chết ⇒ FAIL, nêu .claude/commands/ghost.md" \
    || fail "d. health FAIL nhưng không nêu tên link chết" ;;
  *) fail "d. health không FAIL với link chết: $res | $(printf '%s\n' "$out" | grep -i 'broken\|ghost' | head -2 | tr '\n' ' ')" ;; esac

# ── e. link hợp lệ luôn có dòng exclude (audit Antigravity): phiên kia thắng cuộc đua tạo link ──
#   e1. khe (b): link đã có trước lúc relink() tạo (sau missing()) ⇒ vẫn ghi /rel vào exclude, không tính là "not restorable";
#   e2. khe (a): os.symlink gặp FileExistsError (link vừa được phiên kia tạo) ⇒ vẫn ghi exclude;
#   e3. hai relink song song (lặp 3 lần) trên cùng repo ⇒ mỗi link có đúng một dòng exclude, không mất, không trùng; status sạch.
E="$TMP/e"; mkdir -p "$E/.agents/skills" "$E/.agents/context" "$E/.claude/commands"
printf '{"profile":"backend"}\n' > "$E/.agents/active-profile.json"; printf '{"hooks":{}}\n' > "$E/.claude/settings.json"
: > "$E/.agents/skills/.keep"; : > "$E/.agents/context/.keep"; : > "$E/.claude/commands/.keep"
printf '.claude/audit-gate/\n' > "$E/.gitignore"   # relink.log của CLI, không phải link
( cd "$E" && git init -q -b main . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
EX="$E/.git/info/exclude"
out="$(python3 - "$RELINK" "$E" "$DEVKIT_DIR" <<'PY'
import importlib.util, os, subprocess, sys
relink_py, proj, kit = sys.argv[1:]
spec = importlib.util.spec_from_file_location("relink_check", relink_py)
rc = importlib.util.module_from_spec(spec); spec.loader.exec_module(rc)
rel = ".agents/skills/gate-full"; dst = os.path.join(proj, rel); ex = os.path.join(proj, ".git", "info", "exclude")
def lines():
    try:
        return open(ex, encoding="utf-8").read().splitlines()
    except OSError:
        return []
def status():
    return subprocess.run(["git", "-C", proj, "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
# e1: phiên kia đã tạo link (đúng đích) trước khi relink() tới; exclude chưa có dòng
os.symlink(os.path.join(kit, "skills", "gate-full"), dst)
raced = []; left = rc.relink(proj, [rel], raced)
print("e1", lines().count("/" + rel), rel in left, repr(status()))
# e2: link chưa có lúc kiểm, os.symlink thua cuộc đua (tạo xong rồi FileExistsError như khi phiên kia vừa tạo)
os.unlink(dst); open(ex, "w").write("\n".join(l for l in lines() if l != "/" + rel) + "\n")
real = os.symlink
def racing(src, d, *a, **k):
    real(src, d, *a, **k)
    raise FileExistsError(17, "File exists", d)
rc.os.symlink = racing
try:
    raced = []; left = rc.relink(proj, [rel], raced)
finally:
    rc.os.symlink = real
print("e2", lines().count("/" + rel), rel in left, repr(status()))
PY
)"
case "$out" in *"e1 1 False ''"*) ok "e1. link có sẵn trước relink() (khe b): exclude có đúng một dòng, không 'not restorable', status sạch" ;;
  *) fail "e1. link có sẵn: exclude thiếu dòng / status bẩn: $(printf '%s' "$out" | tr '\n' ' ')" ;; esac
case "$out" in *"e2 1 False ''"*) ok "e2. FileExistsError khi tạo link (khe a): exclude có đúng một dòng, status sạch" ;;
  *) fail "e2. FileExistsError: exclude thiếu dòng / status bẩn: $(printf '%s' "$out" | tr '\n' ' ')" ;; esac
bad=""
for i in 1 2 3; do
  find "$E/.agents/skills" "$E/.claude/commands" -mindepth 1 -maxdepth 1 -type l -exec rm -f {} + ; rm -f "$E/.agents/devkit"
  printf '# git ls-files --others --exclude-from=.git/info/exclude\n' > "$EX"
  python3 "$RELINK" "$E" --quiet --links-only & p1=$!
  python3 "$RELINK" "$E" --quiet --links-only & p2=$!
  wait "$p1"; wait "$p2"
  n=0
  for l in "$E"/.agents/skills/* "$E"/.claude/commands/* "$E/.agents/devkit"; do
    [ -L "$l" ] || continue
    n=$((n + 1)); r="/${l#$E/}"
    [ "$(grep -cxF "$r" "$EX")" = 1 ] || bad="$bad lượt$i:$r=$(grep -cxF "$r" "$EX")"
  done
  [ "$n" -gt 2 ] || bad="$bad lượt$i:chỉ $n link"
  [ -z "$(git -C "$E" status --porcelain)" ] || bad="$bad lượt$i:status=$(git -C "$E" status --porcelain | head -2 | tr '\n' ' ')"
  [ "$(grep -c . "$EX")" = "$(( $(sort -u "$EX" | grep -c .) ))" ] || bad="$bad lượt$i:dòng trùng"
done
[ -z "$bad" ] && ok "e3. hai relink song song x3: mỗi link đúng một dòng exclude, không mất, không trùng, status sạch" \
  || fail "e3. relink song song làm mất / trùng dòng exclude:$bad"

# e4 (OCR #644): bên ghi exclude KHÔNG lấy exclude.lock (worktree.py append dòng secret, install.sh) append giữa lúc relink đọc và ghi
#   ⇒ relink không được ghi đè cả file: dòng secret.env còn, dòng của relink có, mỗi dòng một lần. Móc: open() của module đọc exclude
#   rồi append như worktree.py (O_APPEND); đếm số lần móc chạy để biết cuộc đua thật sự được chèn.
printf '# head\n' > "$EX"
out="$(python3 - "$RELINK" "$E" <<'PY'
import builtins, importlib.util, os, sys
relink_py, proj = sys.argv[1:]
spec = importlib.util.spec_from_file_location("relink_check", relink_py)
rc = importlib.util.module_from_spec(spec); spec.loader.exec_module(rc)
ex = os.path.realpath(os.path.join(proj, ".git", "info", "exclude")); rel = ".agents/skills/zz-e4"; fired = [0]
class Racing:
    def __init__(self, fh): self.fh = fh
    def __enter__(self): return self
    def __exit__(self, *a): self.fh.close()
    def read(self, *a):
        data = self.fh.read(*a)
        fd = os.open(ex, os.O_WRONLY | os.O_APPEND)
        try:
            os.write(fd, b"secret.env\n")
        finally:
            os.close(fd)
        fired[0] += 1
        return data
def racing_open(path, mode="r", *a, **k):
    fh = builtins.open(path, mode, *a, **k)
    return Racing(fh) if os.path.realpath(path) == ex and "r" in mode and "+" not in mode else fh
rc.open = racing_open
try:
    with rc.exclude_lock(proj) as common:
        rc.keep_out_of_git(proj, rel, common)
finally:
    del rc.open
lines = builtins.open(ex, encoding="utf-8").read().splitlines()
print("e4", fired[0], lines.count("secret.env"), lines.count("/" + rel), lines.count("# head"))
PY
)"
case "$out" in *"e4 1 1 1 1"*) ok "e4. bên ghi khác append secret.env giữa lúc relink đọc và ghi: dòng đó còn, dòng relink có, không trùng" ;;
  *) fail "e4. relink ghi đè exclude, mất dòng của bên khác (fired secret relink head): $(printf '%s' "$out" | tr '\n' ' ') | $(tr '\n' '|' < "$EX")" ;; esac

[ "$FAILS" -eq 0 ] && { echo "✅ test_relink_new_kit_items: all passed"; exit 0; }
echo "❌ test_relink_new_kit_items: $FAILS failed"; exit 1
