#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-stop.sh: lệnh stop của một repo chỉ dừng runner và worker CỦA repo đó.
#
# 17/10 07:54: `super-board-stop.sh agent-workbench` gửi SIGTERM 10 tiến trình dispatcher của cả 5 board, vì
# `pgrep -f 'super-board-run\.sh'` khớp mọi runner trên máy (và shell `sh -c … nohup …` bọc ngoài từng runner);
# worker đang chạy của agent-workbench bị Killed: 9. Test chạy stop.sh thật (hộp đen) trong một repo giả; ps,
# pgrep, lsof, gh là stub trên PATH và bảng tiến trình giả chỉ chứa PID của các `sleep` do test này tạo, nên bản
# lỗi có chạy cũng không đụng tiến trình thật nào. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/sb-stop-test.XXXXXX")" && pwd)"   # pwd: TMPDIR có / cuối sinh ra `//`
SLEEPS=""
cleanup() {
  for p in $SLEEPS; do kill "$p" 2>/dev/null || true; done   # chỉ các tiến trình sleep do test này tạo
  [ -n "${KEEP:-}" ] && cat "$TMP/out" || true; rm -rf "$TMP"
}
trap cleanup EXIT

# spawn: đặt S = PID một `sleep` đã tách khỏi shell test (cha là launchd, chết là được dọn ngay, không thành zombie
# khiến kill -0 vẫn thấy sống).
spawn() { S=$( (sleep 300 >/dev/null 2>&1 & echo $!) ); SLEEPS="$SLEEPS $S"; }
alive() { kill -0 "$1" 2>/dev/null; }

A="$TMP/repos/Repo"     # repo chạy lệnh stop
B="$TMP/repos/Repo-2"   # repo khác, tên bắt đầu bằng tên A
mkdir -p "$A/.claude/bin" "$A/.claude/super-board/configs" "$A/.claude/super-board/inflight" "$B"
cp "$ROOT/.claude/bin/super-board-stop.sh" "$ROOT/.claude/bin/super-board-run.sh" "$A/.claude/bin/"
echo '{}' > "$A/.claude/super-board/configs/repo.json"

# Stub trên PATH: stop.sh chạy bằng một bash riêng nên không thừa hưởng hàm shell của test.
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/ps" <<'SH'
#!/usr/bin/env bash
# Bảng tiến trình giả cho lệnh liệt kê; ps theo PID (-p) vẫn chạy ps thật trên các sleep của test.
# `-o ppid=` (startup_orphan_workers, #237): tiến trình giả có cha là launchd (1), nên không phải con của wrapper nào.
case " $* " in
  *" -A "*ppid=*) awk '{ pid = $1; $1 = ""; print pid, 1 $0 }' "$STUB_PS" ;;
  *" -A "*|*" -ax "*|*" aux "*) cat "$STUB_PS" ;;
  *) exec /bin/ps "$@" ;;
esac
SH
cat > "$STUB/pgrep" <<'SH'
#!/usr/bin/env bash
pat=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && { shift; pat="$1"; }; shift; done
grep -E -- "$pat" "$STUB_PS" | awk '{print $1}'
SH
cat > "$STUB/lsof" <<'SH'
#!/usr/bin/env bash
# Chỉ hỗ trợ `lsof -a -p <pid> -d cwd -Fn`; PID không có trong $STUB_CWD thì không in gì (không xác minh được).
pid=""; while [ $# -gt 0 ]; do [ "$1" = "-p" ] && { shift; pid="$1"; }; shift; done
cwd=$(awk -v p="$pid" '$1 == p { $1 = ""; sub(/^ /, ""); print; exit }' "$STUB_CWD")
[ -n "$cwd" ] && printf 'p%s\nfcwd\nn%s\n' "$pid" "$cwd"
exit 0
SH
cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_GH_CALLS"; exit 1
SH
chmod +x "$STUB"/*
export STUB_PS="$TMP/ps.txt" STUB_CWD="$TMP/cwd.txt" STUB_GH_CALLS="$TMP/gh.calls"
: > "$STUB_CWD"; : > "$STUB_GH_CALLS"

# An toàn trước tiên: stub nào không che được lệnh thật thì dừng, không chạy stop.sh.
for c in ps pgrep lsof gh; do
  got=$(env PATH="$STUB:$PATH" bash -c "type -P $c")
  [ "$got" = "$STUB/$c" ] || { echo "✖ stub $c not first on PATH (got '$got'): refusing to run stop.sh"; exit 1; }
done

wline() {   # wline <root>: dòng lệnh worker đúng dạng prompt của dispatch_lane
  printf "claude --dangerously-skip-permissions -p First operation: run .claude/bin/super-board-skills-ready.py --root '%s' --host claude --cards - --lane 'build' --hydrate with [] as stdin. Run super-build on issue #5 for super-board run. Config: x." "$1"
}
spawn; rA=$S;      spawn; rArel=$S;   spawn; rArelX=$S;  spawn; rAoth=$S
spawn; rB=$S;      spawn; rBrel=$S;   spawn; wrapB=$S
spawn; wA=$S;      spawn; wB=$S;      spawn; diag=$S
{
  echo "$rA bash $A/.claude/bin/super-board-run.sh repo"               # runner của A: dừng
  echo "$rArel bash .claude/bin/super-board-run.sh repo"               # runner của A chạy đường dẫn tương đối: dừng
  echo "$rArelX bash .claude/bin/super-board-run.sh repo"              # tương đối, không đọc được cwd: không đụng
  echo "$rAoth bash $A/.claude/bin/super-board-run.sh other"           # runner của A nhưng slug khác: không đụng
  echo "$rB bash $B/.claude/bin/super-board-run.sh repo"               # repo B cùng slug: không đụng
  echo "$rBrel bash .claude/bin/super-board-run.sh repo"               # repo B, tương đối: không đụng
  echo "$wrapB /bin/sh -c cd '$B' && SB_DAEMON=1 nohup '$B/.claude/bin/super-board-run.sh' repo > '$B/docs/super-board/runner.log' 2>&1 &"
  echo "$wA $(wline "$A")"                                             # worker của A không lock: dừng
  echo "$wB $(wline "$B")"                                             # worker của B: không đụng
  echo "$diag /bin/zsh -c grep -c \"bash $A/.claude/bin/super-board-run.sh repo\" runner.log"   # shell chẩn đoán
} > "$STUB_PS"
printf '%s %s\n%s %s\n' "$rArel" "$A" "$rBrel" "$B" > "$STUB_CWD"

# inflight/ holding no issue lock but something else (the runner's early-deaths/ ledger, #94): no worker to clear; under bash 3.2
# `for entry in "${WORKERS[@]}"` on the empty array is "unbound variable" with set -u, and stop exits 1 before its summary
mkdir -p "$A/.claude/super-board/inflight/early-deaths" && echo "1 build" > "$A/.claude/super-board/inflight/early-deaths/7"
( cd "$TMP" && env PATH="$STUB:$PATH" bash "$A/.claude/bin/super-board-stop.sh" repo ) > "$TMP/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "stop exits 0" || { fail "stop exited $rc"; sed 's/^/    /' "$TMP/out"; }

expect_dead() { alive "$1" && fail "$2: pid $1 still running (stop must end it)" || ok "$2: stopped"; }
expect_alive() { alive "$1" && ok "$2: untouched" || fail "$2: pid $1 was killed by repo A's stop"; }
expect_dead  "$rA"    "repo A runner (absolute path)"
expect_dead  "$rArel" "repo A runner (relative path, cwd = A)"
expect_dead  "$wA"    "repo A worker without a lock"
expect_alive "$rB"    "repo B runner (name starts with A's, same slug)"
expect_alive "$rBrel" "repo B runner (relative path, cwd = B)"
expect_alive "$wrapB" "repo B nohup wrapper shell"
expect_alive "$wB"    "repo B worker"
expect_alive "$rAoth" "repo A runner of another slug"
expect_alive "$rArelX" "relative runner whose cwd cannot be read"
expect_alive "$diag"  "diagnostic shell naming A's runner"
[ ! -s "$STUB_GH_CALLS" ] && ok "no GitHub call without in-flight locks" || fail "unexpected gh calls: $(tr '\n' ';' < "$STUB_GH_CALLS")"

[ "$FAILS" -eq 0 ] && echo "✅ test_stop_scope: all passed" || { echo "❌ test_stop_scope: $FAILS failed"; exit 1; }
