#!/usr/bin/env bash
# 25/10 (agent-workbench): cleanup-wt (hook --post-merge của merge gate, --auto ở SessionStart) gỡ worktree dropped-card-sweep lúc 12:35
# vì "merged: ancestor of main" trong khi phiên vẫn ở trong đó và gate --full đang chạy: gate mất thư mục, phiên mất cwd. cleanup-wt
# (mọi bản đã cài ở mọi repo) chỉ chừa worktree bị `git worktree lock`. K11 chỉ khoá khi ExitWorktree keep, và còn MỞ khoá khi phiên vào
# lại — đúng lúc phiên đang làm việc trong đó thì không có khoá nào.
#   E1 trunk mode: PostToolUse EnterWorktree khoá worktree `devkit-kept session=<sid> pid=<tiến trình phiên>`
#   E2 công cụ ngoài (git worktree remove không --force, như cleanup-wt chừa worktree khoá) không gỡ được nó
#   E3 `worktree remove` của kit do chính phiên gọi (đường WorktreeRemove của ExitWorktree remove) vẫn gỡ được: mở khoá của chính nó
#   E4 trunk mode tắt: EnterWorktree không khoá (harness tự `git worktree remove`, khoá sẽ chặn ExitWorktree remove) — như cũ
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null
unset WORKTREE_TRUNK_MODE WORKTREE_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"; SWPY="$DEVKIT_DIR/hooks/session_worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() {   # repo <name> <true|false>: main checkout, trunk mode bật/tắt
  local m="$TMP/$1"; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config devkit.trunkMode "$2" \
    && G "$m" config user.name t && G "$m" config user.email t@t
}
wtadd() {   # wtadd <main> <name> <session>: worktree dựng như hook WorktreeCreate
  (cd "$1" && python3 -I "$WTPY" add "$1/.claude/worktrees/$2" --session="$3" --no-init >/dev/null 2>&1) || fail "setup: add $2"
}
enter() {   # enter <main> <name> <session>: PostToolUse EnterWorktree (cha của python là shell này: pid phiên còn sống = $$)
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],"tool_name":"EnterWorktree","tool_input":{"name":sys.argv[3]},"tool_response":{"worktreePath":sys.argv[2]+"/.claude/worktrees/"+sys.argv[3]}}))' \
    "$3" "$1" "$2" | CLAUDE_PROJECT_DIR="$1" python3 -I "$SWPY" record 2> "$TMP/rec.err"
}
lock_of() { G "$1" worktree list --porcelain | awk -v p="$1/.claude/worktrees/$2" '$1 == "worktree" { cur = $2 } $1 == "locked" && cur == p { sub(/^locked ?/, ""); print }'; }
# #406: thời điểm khởi động của pid nằm CẠNH khoá, trong git dir của worktree (<main>/.git/worktrees/<tên>/devkit-kept.start = "<pid> <start>"):
#   lý do khoá giữ đúng dạng cũ, vì super-board-post-merge-clean.sh của 4 repo app (kit symlink sang đây) đọc nó bằng regex neo cuối
start_file() { echo "$(G "$1/.claude/worktrees/$2" rev-parse --absolute-git-dir)/devkit-kept.start"; }

# E1 + E2 + E3: trunk mode
repo a true; wtadd "$TMP/a" live s1; enter "$TMP/a" live s1
lk="$(lock_of "$TMP/a" live)"; st="$(cat "$(start_file "$TMP/a" live)" 2>/dev/null)"
[ "$lk" = "devkit-kept session=s1 pid=$$" ] && [[ "$st" =~ ^$$\ [^[:space:]]+$ ]] \
  && ok "E1: EnterWorktree (trunk mode) locks the session's worktree devkit-kept with its pid (old reason form), its start time beside it" \
  || fail "E1: lock='$lk' start='$st' err=$(head -c 300 "$TMP/rec.err")"
# F1 (#406 N3): finish báo đúng lý do giữ worktree — khoá devkit-kept của phiên còn sống, không phải "ExitWorktree keep"
(cd "$TMP/a" && python3 -I "$WTPY" finish "$TMP/a/.claude/worktrees/live" > "$TMP/fin.out" 2>&1)
grep -q "live session s1 holds its devkit-kept lock" "$TMP/fin.out" && ! grep -q "ExitWorktree keep" "$TMP/fin.out" \
  && ok "F1: finish says the worktree is kept because a live session holds its devkit-kept lock" \
  || fail "F1: finish output: $(head -c 300 "$TMP/fin.out")"
G "$TMP/a" worktree remove "$TMP/a/.claude/worktrees/live" >/dev/null 2>&1
[ -d "$TMP/a/.claude/worktrees/live" ] && ok "E2: an outside tool (git worktree remove, no --force) cannot remove it while the session lives" \
  || fail "E2: the live session's worktree was removed by a plain git worktree remove"
(cd "$TMP/a" && python3 -I "$WTPY" remove "$TMP/a/.claude/worktrees/live" > "$TMP/rm.out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/a/.claude/worktrees/live" ] && ok "E3: the session's own kit 'worktree remove' (ExitWorktree remove path) still removes it" \
  || fail "E3 (rc $rc): $(head -c 300 "$TMP/rm.out")"

# E4: trunk mode tắt: không khoá
repo b false; wtadd "$TMP/b" plain s2; enter "$TMP/b" plain s2
lk="$(lock_of "$TMP/b" plain)"
[ -z "$lk" ] && ok "E4: trunk mode off: EnterWorktree does not lock (harness git worktree remove keeps working)" || fail "E4: locked '$lk'"

# E5 (review 25/10): ExitWorktree remove mà WorktreeRemove từ chối (worktree còn commit chưa vào main): khoá của phiên phải được mở,
#    nếu không Stop thấy "kept by a live session", bỏ khỏi nợ, và worktree mồ côi
exitwt() {   # exitwt <main> <session> <action>
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],"tool_name":"ExitWorktree","tool_input":{"action":sys.argv[3]},"tool_response":{}}))' \
    "$2" "$1" "$3" | CLAUDE_PROJECT_DIR="$1" python3 -I "$SWPY" record 2> "$TMP/rec.err"
}
repo c true; wtadd "$TMP/c" unmerged s5; enter "$TMP/c" unmerged s5
echo x > "$TMP/c/.claude/worktrees/unmerged/x.txt" && G "$TMP/c/.claude/worktrees/unmerged" add x.txt && G "$TMP/c/.claude/worktrees/unmerged" commit -qm x
[ -n "$(lock_of "$TMP/c" unmerged)" ] || fail "E5 setup: not locked after enter"
exitwt "$TMP/c" s5 remove
lk="$(lock_of "$TMP/c" unmerged)"
[ -z "$lk" ] && ok "E5: ExitWorktree remove (removal refused, work not in main): the session's lock is released for the Stop to adopt" \
  || fail "E5: still locked '$lk' after ExitWorktree remove"
# E5b: /clear đổi sid nhưng cùng tiến trình: khoá mang sid cũ, pid hiện tại — vẫn là của phiên này, ExitWorktree remove mở được
repo d true; wtadd "$TMP/d" cleared s6; enter "$TMP/d" cleared s6
mkdir -p "$TMP/d/.claude/audit-gate/session_worktree" && printf '%s\npid %s\n' "$TMP/d/.claude/worktrees/cleared" $$ > "$TMP/d/.claude/audit-gate/session_worktree/s7"
exitwt "$TMP/d" s7 remove
lk="$(lock_of "$TMP/d" cleared)"
[ -z "$lk" ] && ok "E5b: after /clear (new sid, same process) ExitWorktree remove still releases the old-sid lock by its pid" \
  || fail "E5b: still locked '$lk'"

# E6 (review 25/10): phiên KHỞI ĐỘNG sẵn trong worktree (Desktop worktree session, claude --worktree): không có EnterWorktree,
#    SessionStart phải khoá. E7: trunk mode tắt thì không.
start_in() {   # start_in <main> <name> <session>
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"SessionStart","cwd":sys.argv[2],"source":"startup"}))' \
    "$3" "$1/.claude/worktrees/$2" | CLAUDE_PROJECT_DIR="$1/.claude/worktrees/$2" DEVKIT_SCRATCH_CLEANUP=0 python3 -I "$DEVKIT_DIR/bin/session_lock.py" > /dev/null 2> "$TMP/start.err"
}
repo e true; wtadd "$TMP/e" started s8; start_in "$TMP/e" started s8
lk="$(lock_of "$TMP/e" started)"
[ "$lk" = "devkit-kept session=s8 pid=$$" ] && ok "E6: a session that STARTS in a worktree (trunk mode) gets it locked at SessionStart" \
  || fail "E6: lock='$lk' err=$(head -c 300 "$TMP/start.err")"
repo f false; wtadd "$TMP/f" started s9; start_in "$TMP/f" started s9
lk="$(lock_of "$TMP/f" started)"
[ -z "$lk" ] && ok "E7: trunk mode off: SessionStart does not lock" || fail "E7: locked '$lk'"
# E8: worktree lane của super-board: runner gỡ nó bằng `git worktree remove` thô — khoá của worker đã chết sẽ chặn, nên không khoá
wtadd "$TMP/e" issue-12-build s10; start_in "$TMP/e" issue-12-build s10
lk="$(lock_of "$TMP/e" issue-12-build)"
[ -z "$lk" ] && ok "E8: a super-board lane worktree (issue-12-build) is not locked at SessionStart (the board removes it itself)" \
  || fail "E8: board lane worktree locked '$lk'"

# #406 N1: cwd của SessionStart đi theo `cd` (transcript 25/10: cwd đổi giữa phiên không qua EnterWorktree). compact / clear giữ nguyên
#   tiến trình claude, khoá nó đã đặt lúc khởi động vẫn còn — SessionStart chỉ khoá khi tiến trình MỚI (startup, resume, fork) và pid đó
#   chưa giữ khoá devkit-kept nào trong repo; nếu không, phiên đứng (cd) trong worktree của phiên khác sẽ khoá nó bằng pid của mình.
start_src() {   # start_src <main> <worktree name> <session> <source>
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"SessionStart","cwd":sys.argv[2],"source":sys.argv[3]}))' \
    "$3" "$1/.claude/worktrees/$2" "$4" | CLAUDE_PROJECT_DIR="$1/.claude/worktrees/$2" DEVKIT_SCRATCH_CLEANUP=0 python3 -I "$DEVKIT_DIR/bin/session_lock.py" > /dev/null 2> "$TMP/start.err"
}
# E9: compact sau khi cd vào worktree của phiên khác: không khoá
repo g true; wtadd "$TMP/g" peer s21; start_src "$TMP/g" peer s20 compact
lk="$(lock_of "$TMP/g" peer)"
[ -z "$lk" ] && ok "E9: SessionStart compact after a cd into another session's worktree does not lock it" || fail "E9: peer worktree locked '$lk'"
start_src "$TMP/g" peer s20 clear
lk="$(lock_of "$TMP/g" peer)"
[ -z "$lk" ] && ok "E9b: SessionStart clear after a cd into another session's worktree does not lock it either" || fail "E9b: peer worktree locked '$lk'"
# E10: /clear trong worktree đã khoá lúc khởi động: không khoá mới, khoá cũ (cùng tiến trình) vẫn còn
wtadd "$TMP/g" mine s22; start_src "$TMP/g" mine s22 startup; before="$(lock_of "$TMP/g" mine)"
start_src "$TMP/g" mine s23 clear; after="$(lock_of "$TMP/g" mine)"
[ -n "$before" ] && [ "$after" = "$before" ] && ok "E10: /clear keeps the startup lock of the same process unchanged" \
  || fail "E10: before='$before' after='$after' err=$(head -c 300 "$TMP/start.err")"
# E11: resume từ shell (tiến trình mới, id mới) trong worktree mà khoá cũ mang pid đã chết: khoá lại bằng pid mới
DEAD=99999; while kill -0 "$DEAD" 2>/dev/null; do DEAD=$((DEAD - 1)); done
repo h true; wtadd "$TMP/h" resumed s24; G "$TMP/h" worktree lock --reason "devkit-kept session=s24 pid=$DEAD" "$TMP/h/.claude/worktrees/resumed"
start_src "$TMP/h" resumed s25 resume
lk="$(lock_of "$TMP/h" resumed)"
[ "$lk" = "devkit-kept session=s25 pid=$$" ] && ok "E11: a shell resume (new process) in its worktree takes the lock over from the dead pid" \
  || fail "E11: lock='$lk' err=$(head -c 300 "$TMP/start.err")"
# E12: /resume trong phiên (cùng tiến trình) sau khi cd vào worktree khác: pid đã giữ khoá worktree của nó, không khoá thêm
repo i true; wtadd "$TMP/i" own s26; enter "$TMP/i" own s26; wtadd "$TMP/i" other s27
start_src "$TMP/i" other s28 resume
lk="$(lock_of "$TMP/i" other)"
[ -z "$lk" ] && [ -n "$(lock_of "$TMP/i" own)" ] && ok "E12: an in-session /resume after a cd does not lock a second worktree (the pid already holds one)" \
  || fail "E12: other='$lk' own='$(lock_of "$TMP/i" own)'"
# E13 (OCR 25/10): một tiến trình MỚI (startup) chỉ trùng pid với khoá ở worktree khác khi pid bị cấp lại: nó vẫn khoá worktree của nó
wtadd "$TMP/i" fresh s29; start_src "$TMP/i" fresh s29 startup
lk="$(lock_of "$TMP/i" fresh)"
[ "$lk" = "devkit-kept session=s29 pid=$$" ] && ok "E13: a fresh startup still locks its worktree when its pid matches a lock elsewhere (pid reuse)" \
  || fail "E13: lock='$lk' err=$(head -c 300 "$TMP/start.err")"

# #406 R: pid của khoá còn sống nhưng thời điểm khởi động khác = OS đã cấp pid đó cho tiến trình khác: khoá chết. Không đọc được thời điểm
#   khởi động (ps hỏng): coi là còn sống (thà giữ worktree thừa còn hơn gỡ worktree của phiên đang chạy).
sleep 300 & SLEEPER=$!; disown "$SLEEPER"   # tiến trình sống, không phải tổ tiên của lệnh remove (khoá của chính phiên gọi luôn mở được: E3)
trap 'kill "$SLEEPER" 2>/dev/null; rm -rf "$TMP"' EXIT
repo r true
BOGUS="Mon_Jan__1_00:00:00_2001"   # thời điểm khởi động không phải của tiến trình SLEEPER (dạng ps; Linux đọc /proc: dạng proc:)
[ -r "/proc/$SLEEPER/stat" ] && BOGUS="proc:1"
lock_with() {   # lock_with <worktree name> <session> [<pid> <start>]: khoá dạng cũ của SLEEPER, thời điểm khởi động ghi cạnh (nếu có)
  G "$TMP/r" worktree lock --reason "devkit-kept session=$2 pid=$SLEEPER" "$TMP/r/.claude/worktrees/$1"
  [ -z "${3:-}" ] || printf '%s %s\n' "$3" "$4" > "$(start_file "$TMP/r" "$1")"
}
wtadd "$TMP/r" reused s30; lock_with reused s30 "$SLEEPER" "$BOGUS"
(cd "$TMP/r" && python3 -I "$WTPY" remove "$TMP/r/.claude/worktrees/reused" > "$TMP/rm.out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$TMP/r/.claude/worktrees/reused" ] && ok "R1: a live pid whose start time differs from the lock's (pid reused) reads dead: remove unlocks and removes" \
  || fail "R1 (rc $rc): $(head -c 300 "$TMP/rm.out")"
wtadd "$TMP/r" oldfmt s31; lock_with oldfmt s31
(cd "$TMP/r" && python3 -I "$WTPY" remove "$TMP/r/.claude/worktrees/oldfmt" > "$TMP/rm.out" 2>&1); rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/r/.claude/worktrees/oldfmt" ] && ok "R2: a lock with no start time beside it (older kit) of a live pid still holds the worktree" \
  || fail "R2 (rc $rc): removed a live session's worktree"
wtadd "$TMP/r" otherpid s36; lock_with otherpid s36 "$DEAD" "$BOGUS"   # the start time of ANOTHER pid (an older lock's): not this lock's
(cd "$TMP/r" && python3 -I "$WTPY" remove "$TMP/r/.claude/worktrees/otherpid" > "$TMP/rm.out" 2>&1); rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/r/.claude/worktrees/otherpid" ] && ok "R5: a start time recorded for another pid does not judge this lock (live pid: kept)" \
  || fail "R5 (rc $rc): removed a live session's worktree on another pid's start time"
# R4: EnterWorktree vào worktree mà khoá của phiên KHÁC mang pid đã bị cấp lại: thay bằng khoá của phiên này
wtadd "$TMP/r" taken s33; lock_with taken s34 "$SLEEPER" "$BOGUS"
enter "$TMP/r" taken s33
lk="$(lock_of "$TMP/r" taken)"; st="$(cat "$(start_file "$TMP/r" taken)" 2>/dev/null)"
[ "$lk" = "devkit-kept session=s33 pid=$$" ] && [[ "$st" =~ ^$$\ [^[:space:]]+$ ]] && ok "R4: EnterWorktree replaces another session's lock whose pid was reused (and its start time)" \
  || fail "R4: lock='$lk' start='$st' err=$(head -c 300 "$TMP/rec.err")"
# R6/R7 (OCR 25/10): khoá mới không bao giờ đứng cạnh thời điểm khởi động CŨ của cùng pid (pid đã bị cấp lại cho tiến trình này) — nếu không,
#   khoá của phiên đang sống đọc thành chết và remove/gc/automerge gỡ worktree dưới chân nó. R6: không biết thời điểm khởi động mới: file cũ
#   bị xoá. R7: ghi file mới hỏng (đĩa đầy, os.replace lỗi): file cũ cũng không còn.
wtadd "$TMP/r" stale s38; sf="$(start_file "$TMP/r" stale)"
side() {   # side <start|None> [replace-fails|tmp-blocked]: _write_kept_start(worktree stale, pid of this shell, start), a fault on demand
  python3 -I -c 'import os, sys
sys.path.append(sys.argv[1]); import session_worktree as sw
if sys.argv[5:] == ["replace-fails"]:
    def broken(*a, **k): raise OSError(28, "No space left on device")
    os.replace = broken
if sys.argv[5:] == ["tmp-blocked"]:   # an entry that cannot be unlinked where the temp file goes
    os.makedirs(os.path.join(sw._admin_dir(sys.argv[2]), sw.KEPT_START + f".{os.getpid()}.tmp", "x"))
sw._write_kept_start(sys.argv[2], int(sys.argv[3]), None if sys.argv[4] == "None" else sys.argv[4])' \
    "$DEVKIT_DIR/hooks" "$TMP/r/.claude/worktrees/stale" "$$" "$@" 2> "$TMP/side.err"
}
printf '%s %s\n' "$$" "$BOGUS" > "$sf"; side None
[ ! -e "$sf" ] && ok "R6: no start time known for the new lock: an older start time of the same pid is dropped" || fail "R6: still '$(cat "$sf")'"
printf '%s %s\n' "$$" "$BOGUS" > "$sf"; side NEW_START replace-fails
[ ! -e "$sf" ] || [ "$(cat "$sf")" = "$$ NEW_START" ] && ok "R7: the new start time cannot be written: the older one of the same pid is gone too" \
  || fail "R7: stale '$(cat "$sf")' left beside the new lock; err=$(head -c 200 "$TMP/side.err")"
[ -z "$(ls "$(dirname "$sf")" | grep 'devkit-kept.start\..*\.tmp')" ] && ok "  … and no temp file is left in the worktree's git dir" \
  || fail "R7: temp file left: $(ls "$(dirname "$sf")" | grep tmp)"
printf '%s %s\n' "$$" "$BOGUS" > "$sf"; side NEW_START tmp-blocked
[ ! -e "$sf" ] || [ "$(cat "$sf")" = "$$ NEW_START" ] && ok "R7b: an entry that cannot be removed where the temp file goes: the older start time is gone all the same" \
  || fail "R7b: stale '$(cat "$sf")' left beside the new lock; err=$(head -c 200 "$TMP/side.err")"
rm -rf "$(dirname "$sf")"/devkit-kept.start.*.tmp

# E14 (OCR 25/10): /resume của một phiên CHƯA giữ khoá nào (đang ở main, cd vào worktree khác): worktree có chủ khác CÒN SỐNG (registry
#   mang pid trả lời) thì không khoá. E14b đối chứng: chủ đã chết (không pid nào sống) thì nhận như reown (worktree không mất việc).
repo j true
wtadd "$TMP/j" peer2 s41; mkdir -p "$TMP/j/.git/devkit-sessions"
printf '{"session_id": "s41", "agent": "claude", "pid": %s}\n' "$SLEEPER" > "$TMP/j/.git/devkit-sessions/s41.json"
start_src "$TMP/j" peer2 s42 resume
lk="$(lock_of "$TMP/j" peer2)"
[ -z "$lk" ] && ok "E14: a resume that holds no lock does not lock a worktree whose owner session is alive" \
  || fail "E14: live owner's worktree locked '$lk' err=$(head -c 300 "$TMP/start.err")"
wtadd "$TMP/j" gone s43; start_src "$TMP/j" gone s44 resume
lk="$(lock_of "$TMP/j" gone)"
[ "$lk" = "devkit-kept session=s44 pid=$$" ] && ok "E14b: … but one whose owner has no live pid anywhere is taken over (the work is never lost)" \
  || fail "E14b: lock='$lk' err=$(head -c 300 "$TMP/start.err")"
# E16 (OCR 25/10): chủ được nêu qua RECORD session_worktree (EnterWorktree), không qua state: record mang pid còn sống thì cũng không khoá
G "$TMP/j" worktree add -q --detach "$TMP/j/.claude/worktrees/recowned"
mkdir -p "$TMP/j/.claude/audit-gate/session_worktree"
printf '%s\npid %s\n' "$TMP/j/.claude/worktrees/recowned" "$SLEEPER" > "$TMP/j/.claude/audit-gate/session_worktree/s50"
start_src "$TMP/j" recowned s51 startup
lk="$(lock_of "$TMP/j" recowned)"
[ -z "$lk" ] && ok "E16: a worktree a live session's record names (no state owner) is not locked by a session standing in it" \
  || fail "E16: locked '$lk' err=$(head -c 300 "$TMP/start.err")"
# E17 (OCR 25/10): devkit-worktree.json lồng quá sâu (hỏng, hay agent ghi): đọc như không có chủ — phiên khởi động trong đó vẫn khoá
wtadd "$TMP/j" deep s52
python3 -c 'import sys; open(sys.argv[1], "w").write("[" * 200000)' "$(G "$TMP/j/.claude/worktrees/deep" rev-parse --absolute-git-dir)/devkit-worktree.json"
start_src "$TMP/j" deep s52 startup
lk="$(lock_of "$TMP/j" deep)"
[ "$lk" = "devkit-kept session=s52 pid=$$" ] && ok "E17: a state file nested too deep reads as no owner: the session starting there still locks it" \
  || fail "E17: lock='$lk' err=$(head -c 300 "$TMP/start.err")"

# R8 (review 25/10): thời điểm khởi động ghi một kiểu (/proc) mà đọc kiểu khác (ps), hay ngược lại: không so được = còn sống
OTHERFMT="proc:1"; [ -r "/proc/$SLEEPER/stat" ] && OTHERFMT="Mon_Jan__1_00:00:00_2001"
wtadd "$TMP/r" xfmt s45; lock_with xfmt s45 "$SLEEPER" "$OTHERFMT"
(cd "$TMP/r" && python3 -I "$WTPY" remove "$TMP/r/.claude/worktrees/xfmt" > "$TMP/rm.out" 2>&1); rc=$?
[ "$rc" != 0 ] && [ -d "$TMP/r/.claude/worktrees/xfmt" ] && ok "R8: a start time recorded in the other format (/proc vs ps) reads alive: the worktree stays" \
  || fail "R8 (rc $rc): removed on a start time it cannot compare"
# E15 (review 25/10): resume mà pid trùng một khoá ở worktree khác nhưng thời điểm khởi động khác (pid đó đã bị cấp lại): vẫn khoá
repo k true
wtadd "$TMP/k" held s46; G "$TMP/k" worktree lock --reason "devkit-kept session=s46 pid=$$" "$TMP/k/.claude/worktrees/held"
printf '%s %s\n' "$$" "$BOGUS" > "$(start_file "$TMP/k" held)"
wtadd "$TMP/k" newer s47; start_src "$TMP/k" newer s48 resume
lk="$(lock_of "$TMP/k" newer)"
[ "$lk" = "devkit-kept session=s48 pid=$$" ] && ok "E15: a resume whose pid matches a lock elsewhere with another start time (pid reused) still locks" \
  || fail "E15: lock='$lk' err=$(head -c 300 "$TMP/start.err")"
# R3: thời điểm khởi động không đọc được (ps hỏng) = còn sống — ở cả remove của kit lẫn EnterWorktree. Linux đọc /proc trước, không qua ps: bỏ qua
if [ -r "/proc/$SLEEPER/stat" ]; then
  ok "R3/R3b: skipped (this system reads start times from /proc, a broken ps cannot hide them)"
else
  mkdir -p "$TMP/nops"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nops/ps"; chmod +x "$TMP/nops/ps"
  wtadd "$TMP/r" nops s32; lock_with nops s32 "$SLEEPER" "$BOGUS"
  (cd "$TMP/r" && PATH="$TMP/nops:$PATH" python3 -I "$WTPY" remove "$TMP/r/.claude/worktrees/nops" > "$TMP/rm.out" 2>&1); rc=$?
  [ "$rc" != 0 ] && [ -d "$TMP/r/.claude/worktrees/nops" ] && ok "R3: start time unreadable (ps fails): the lock reads alive, the worktree stays" \
    || fail "R3 (rc $rc): removed while the start time could not be read"
  wtadd "$TMP/r" nops2 s37; lock_with nops2 s35 "$SLEEPER" "$BOGUS"
  PATH="$TMP/nops:$PATH" enter "$TMP/r" nops2 s37
  lk="$(lock_of "$TMP/r" nops2)"
  [ "$lk" = "devkit-kept session=s35 pid=$SLEEPER" ] && ok "R3b: EnterWorktree with the start time unreadable leaves another live session's lock in place" \
    || fail "R3b: lock='$lk' (another live session's lock was replaced)"
fi

# #413 N1: khoá lúc startup hỏng (git worktree lock thất bại) thì phiên PHẢI được báo (stdout SessionStart -> additionalContext), không im lặng.
#   git giả: `worktree lock` luôn lỗi, mọi lệnh khác chuyển cho git thật.
REALGIT="$(command -v git)"; mkdir -p "$TMP/badgit"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = lock ] && exit 1; done\nexec "%s" "$@"\n' "$REALGIT" > "$TMP/badgit/git"; chmod +x "$TMP/badgit/git"
start_bad() {   # start_bad <main> <worktree name> <session> <source>: như start_src nhưng `git worktree lock` hỏng; stdout giữ lại
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"SessionStart","cwd":sys.argv[2],"source":sys.argv[3]}))' \
    "$3" "$1/.claude/worktrees/$2" "$4" | PATH="$TMP/badgit:$PATH" CLAUDE_PROJECT_DIR="$1/.claude/worktrees/$2" DEVKIT_SCRATCH_CLEANUP=0 python3 -I "$DEVKIT_DIR/bin/session_lock.py" > "$TMP/start.out" 2> "$TMP/start.err"
}
repo n true; wtadd "$TMP/n" bad s60; start_bad "$TMP/n" bad s60 startup
lk="$(lock_of "$TMP/n" bad)"
[ -z "$lk" ] && grep -q "NOT LOCKED" "$TMP/start.out" && ok "N1: a startup whose git lock fails says NOT LOCKED on stdout (additionalContext), SessionStart still passes" \
  || fail "N1: lock='$lk' out=$(head -c 300 "$TMP/start.out") err=$(head -c 200 "$TMP/start.err")"
# N2: ...rồi SessionStart compact (git lành): khoá lại worktree KHỞI ĐẦU của phiên (record), không theo cwd; cd sang worktree phiên khác thì không
wtadd "$TMP/n" peer s61
start_src "$TMP/n" bad s60 compact; lk="$(lock_of "$TMP/n" bad)"
[ "$lk" = "devkit-kept session=s60 pid=$$" ] && ok "N2: compact after a failed startup lock locks the session's own starting worktree" \
  || fail "N2: lock='$lk' err=$(head -c 300 "$TMP/start.err")"
wtadd "$TMP/n" bad2 s62; start_bad "$TMP/n" bad2 s63 startup   # s63: lock failed, record kept
G "$TMP/n" worktree unlock "$TMP/n/.claude/worktrees/bad"   # (the test shell is every session's pid: free it, or "the pid holds a lock" skips)
start_src "$TMP/n" peer s63 compact   # cwd = another session's worktree
[ -z "$(lock_of "$TMP/n" peer)" ] && [ "$(lock_of "$TMP/n" bad2)" = "devkit-kept session=s63 pid=$$" ] \
  && ok "N2b: compact with the cwd moved into another session's worktree locks the session's own one (its record), not that one" \
  || fail "N2b: peer='$(lock_of "$TMP/n" peer)' own='$(lock_of "$TMP/n" bad2)'"
# N1b: git que não responde (lista de worktrees > 5 s): o aviso sai antes de os 10 s do hook, sem mais chamadas git
mkdir -p "$TMP/slowgit"
printf '#!/bin/sh\ncase " $* " in *" worktree list "*) sleep 6;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$TMP/slowgit/git"; chmod +x "$TMP/slowgit/git"
wtadd "$TMP/n" slow s64; t0=$SECONDS
python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"SessionStart","cwd":sys.argv[2],"source":"startup"}))' \
  s64 "$TMP/n/.claude/worktrees/slow" | PATH="$TMP/slowgit:$PATH" CLAUDE_PROJECT_DIR="$TMP/n/.claude/worktrees/slow" DEVKIT_SCRATCH_CLEANUP=0 python3 -I "$DEVKIT_DIR/bin/session_lock.py" > "$TMP/start.out" 2> "$TMP/start.err"
[ $((SECONDS - t0)) -lt 10 ] && grep -q "NOT LOCKED" "$TMP/start.out" \
  && ok "N1b: git that hangs on the worktree list: NOT LOCKED printed within the hook's 10 s budget ($((SECONDS - t0)) s)" \
  || fail "N1b: took $((SECONDS - t0)) s out=$(head -c 200 "$TMP/start.out")"

# #413 N3: pid của chủ còn sống nhưng đã bị cấp lại (thời điểm khởi động khác) = chủ đã đi: phiên mới vẫn khoá. Đối chứng: đúng thời điểm = còn sống.
REGBOGUS="${BOGUS//_/ }"; [ -r "/proc/$SLEEPER/stat" ] && REGBOGUS="proc:1"
REALSTART="$(python3 -I -c 'import sys; sys.path.append(sys.argv[1]); import session_lock as s; print(s.pid_start(int(sys.argv[2])) or "")' "$DEVKIT_DIR/bin" "$SLEEPER")"
repo m true
wtadd "$TMP/m" reg s70; mkdir -p "$TMP/m/.git/devkit-sessions"
printf '{"session_id": "s70", "agent": "claude", "pid": %s, "pid_start": "%s"}\n' "$SLEEPER" "$REGBOGUS" > "$TMP/m/.git/devkit-sessions/s70.json"
start_src "$TMP/m" reg s71 resume
[ "$(lock_of "$TMP/m" reg)" = "devkit-kept session=s71 pid=$$" ] && ok "N3a: owner with a live registry pid but another pid_start (pid reused) reads gone: the new session locks" \
  || fail "N3a: lock='$(lock_of "$TMP/m" reg)' err=$(head -c 300 "$TMP/start.err")"
wtadd "$TMP/m" regok s72
printf '{"session_id": "s72", "agent": "claude", "pid": %s, "pid_start": "%s"}\n' "$SLEEPER" "$REALSTART" > "$TMP/m/.git/devkit-sessions/s72.json"
start_src "$TMP/m" regok s73 resume
[ -z "$(lock_of "$TMP/m" regok)" ] && ok "N3b: same owner with the pid_start that matches stays alive: not locked" \
  || fail "N3b: live owner's worktree locked '$(lock_of "$TMP/m" regok)'"
G "$TMP/m" worktree add -q --detach "$TMP/m/.claude/worktrees/recreuse"
mkdir -p "$TMP/m/.claude/audit-gate/session_worktree"
printf '%s\npid %s\nstart %s\n' "$TMP/m/.claude/worktrees/recreuse" "$SLEEPER" "$BOGUS" > "$TMP/m/.claude/audit-gate/session_worktree/s74"
start_src "$TMP/m" recreuse s75 startup
[ "$(lock_of "$TMP/m" recreuse)" = "devkit-kept session=s75 pid=$$" ] && ok "N3c: a session record whose pid was reused (start time differs) no longer owns the worktree: the new session locks" \
  || fail "N3c: lock='$(lock_of "$TMP/m" recreuse)' err=$(head -c 300 "$TMP/start.err")"
# N3d: EnterWorktree ghi thời điểm khởi động của pid vào record (dòng 3)
repo o true; wtadd "$TMP/o" ent s76; enter "$TMP/o" ent s76
grep -q "^start [^[:space:]]" "$TMP/o/.claude/audit-gate/session_worktree/s76" && ok "N3d: the session record carries the pid's start time (line 3)" \
  || fail "N3d: record: $(cat "$TMP/o/.claude/audit-gate/session_worktree/s76")"

echo
[ "$FAILS" = 0 ] && { echo "test_session_worktree_enter_lock: PASS"; exit 0; }
echo "test_session_worktree_enter_lock: $FAILS FAIL"; exit 1
