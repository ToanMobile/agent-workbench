#!/usr/bin/env bash
# #686 (PR 1 cờ + override + watch, §2.4 của thiết kế v3.1): merge gate chốt việc bật cờ trong .agents/gate-rules.json.
# Nâng một khoá (luật off→on, hoặc TTL tăng) chỉ qua được khi đủ bốn điều kiện — thiếu một là exit 8 (needs-you), ngay ở
# --preflight (train preflight đi qua cùng chỗ):
#   1. blob gate_rules.py ở HEAD_SHA bằng ở BASE_SHA; bộ kiểm chạy bản lấy từ BASE_SHA, không phải bản của PR;
#   2. đúng một khoá được nâng, khoá khác không đổi (kể cả không có khoá nào bị hạ cùng lúc);
#   3. mọi path trong BASE_SHA...HEAD_SHA khớp MANIFEST[khoá] ∪ {.agents/gate-rules.json};
#   4. trailer Freeze-exception không được tính.
# Hạ (on→off, TTL giảm) tự đi tiếp. Bổ sung so với §2.4 (3 lỗ của đoạn mẫu):
#   - python chạy với -I: một json.py nằm ở cwd (PR kiểm soát được) không chiếm được bộ kiểm;
#   - gate_rules.py vắng ở BASE_SHA mà file cờ đổi: bật ⇒ exit 8 (đóng), chỉ file toàn off ⇒ đi tiếp (PR đầu tiên thêm cờ);
#   - so blob bằng `rev-parse --verify -q`, hai phía cùng vắng không bao giờ thành "bằng nhau".
# Repo giả: bare origin + fake gh (như test_merge_gate_devkit_from_main.sh), chạy gate với --preflight: không scratch, không verify.
# Chưa có chốt trong merge gate thì c1–c4 ĐỎ (gate cho đi qua). Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
GR_SRC="$ROOT/universal-agent-devkit/bin/gate_rules.py"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

[ -f "$GR_SRC" ] || { echo "✖ không có universal-agent-devkit/bin/gate_rules.py: chưa có cờ gate-rules (fixture cần bản guard ở BASE)"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "✖ cần jq"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-rules-raise.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset DEVKIT_GATE_RULE_L1 DEVKIT_GATE_RULE_L2 DEVKIT_GATE_RULE_L3 DEVKIT_GATE_RULE_B DEVKIT_GATE_RULE_CACHE SB_MERGE_QUEUE SB_MERGE_CALLER
gg() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

rules_json() { # <L1> <L2> <L3> <B> <ttl>
  printf '{"version": 1, "rules": {"L1": "%s", "L2": "%s", "L3": "%s", "B": "%s"}, "ttl": {"suite_cache_max_s": %s}}\n' "$1" "$2" "$3" "$4" "$5"
}
# mkrepo <name> <guard 0|1> <rules-file 0|1>: bare origin + repo; base có/không gate_rules.py và gate-rules.json (toàn off)
mkrepo() {
  local d="$TMP/$1" o="$TMP/$1.git"
  gg init -q --bare "$o"; gg init -q "$d"
  mkdir -p "$d/.claude/super-board/configs" "$d/.agents"
  echo '{}' > "$d/.claude/super-board/configs/x.json"; echo a > "$d/a"
  if [ "$2" = 1 ]; then mkdir -p "$d/universal-agent-devkit/bin"; cp "$GR_SRC" "$d/universal-agent-devkit/bin/gate_rules.py"; fi
  if [ "$3" = 1 ]; then rules_json off off off off 21600 > "$d/.agents/gate-rules.json"; fi
  ( cd "$d" && gg add -A && gg commit -qm base && gg remote add origin "$o" && gg push -q origin main )
}
# start_pr <repo> <N>: nhánh issue-N-x từ origin/main; finish_pr <repo> <N> [msg]: commit, push, ghi file cho fake gh
start_pr() { ( cd "$TMP/$1" && gg fetch -q origin && gg checkout -q -b "issue-$2-x" origin/main && mkdir -p .agents ); }
finish_pr() {
  local d="$TMP/$1"
  ( cd "$d" && gg add -A && gg commit -qm "${3:-card $2}" && gg push -q origin "issue-$2-x" \
    && git rev-parse HEAD > "$TMP/pr$2.head" \
    && git diff --name-only origin/main > "$TMP/files$2" \
    && git diff origin/main > "$TMP/pr$2.diff" \
    && jq -Rn '[inputs | select(length > 0) | {path: .}]' < "$TMP/files$2" > "$TMP/files$2.json" \
    && git diff --numstat origin/main > "$TMP/num$2" \
    && printf '{"files":%s,"labels":[],"body":"","additions":%s,"deletions":%s,"changedFiles":%s}' "$(cat "$TMP/files$2.json")" \
         "$(awk '{a+=$1} END {print a+0}' "$TMP/num$2")" "$(awk '{d+=$2} END {print d+0}' "$TMP/num$2")" \
         "$(wc -l < "$TMP/files$2" | tr -d ' ')" > "$TMP/pr$2.meta" \
    && gg checkout -q main )
}
# advance_main <repo> <msg>: commit những gì đang sửa ở main rồi push (base của các PR sau)
advance_main() { ( cd "$TMP/$1" && gg add -A && gg commit -qm "$2" && gg push -q origin main ); }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head" 2>/dev/null)
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: must not merge in preflight" >&2; exit 1 ;;
  *" pr comment "*|*" api "*) exit 0 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}\n' > "$CFG"

# run <repo> <N>: gate --preflight; stdout+stderr ở $TMP/run.log, exit code ở $RC
RC=0
run() {
  local h; h="$(cat "$TMP/pr$2.head")"; rm -f "$TMP/halt.json"
  ( cd "$TMP/$1" && bash "$GATE" --config "$CFG" --pr "$2" --expect-head "$h" --preflight ) >"$TMP/run.log" 2>&1; RC=$?
}
expect_through() { # <nhãn> <repo> <N>
  run "$2" "$3"
  if [ "$RC" -eq 0 ] && grep -q "preflight: ok" "$TMP/run.log"; then ok "$1"; else fail "$1 — exit $RC: $(tail -4 "$TMP/run.log")"; fi
}
expect_blocked() { # <nhãn> <repo> <N>
  run "$2" "$3"
  if [ "$RC" -eq 8 ] && grep -q "gate-rules raise not allowed" "$TMP/run.log"; then ok "$1"; else fail "$1 — exit $RC (want 8): $(tail -4 "$TMP/run.log")"; fi
}

# --- R: base có guard + gate-rules.json (toàn off, TTL 21600) -------------------------------------------------------------------
mkrepo R 1 1
start_pr R 1; rules_json off off on off 21600 > "$TMP/R/.agents/gate-rules.json"
mkdir -p "$TMP/R/universal-agent-devkit/bin" && echo '# l3' > "$TMP/R/universal-agent-devkit/bin/l3_gate.py"
mkdir -p "$TMP/R/tests/super-board" && echo '# t' > "$TMP/R/tests/super-board/test_merge_gate_l3_x.sh"; finish_pr R 1
expect_through "ok. bật L3, chỉ chạm path trong MANIFEST[L3] ⇒ đi tiếp (preflight: ok)" R 1

start_pr R 2; rules_json off off on off 21600 > "$TMP/R/.agents/gate-rules.json"
echo '# PR sửa guard' >> "$TMP/R/universal-agent-devkit/bin/gate_rules.py"; finish_pr R 2
expect_blocked "c1. bật L3 và sửa gate_rules.py ⇒ exit 8" R 2

start_pr R 3; rules_json off off on on 21600 > "$TMP/R/.agents/gate-rules.json"; echo '# l3' > "$TMP/R/universal-agent-devkit/bin/l3_gate.py"; finish_pr R 3
expect_blocked "c2a. bật L3 + B cùng lúc ⇒ exit 8" R 3

start_pr R 5; rules_json off off on off 21600 > "$TMP/R/.agents/gate-rules.json"
echo '# l3' > "$TMP/R/universal-agent-devkit/bin/l3_gate.py"; echo '# ngoài manifest' > "$TMP/R/universal-agent-devkit/bin/scoped_gate.py"; finish_pr R 5
expect_blocked "c3. bật L3, có chạm file ngoài MANIFEST[L3] ⇒ exit 8" R 5

start_pr R 6; rules_json off off on off 21600 > "$TMP/R/.agents/gate-rules.json"
echo '# l3' > "$TMP/R/universal-agent-devkit/bin/l3_gate.py"; echo '# ngoài manifest' > "$TMP/R/universal-agent-devkit/bin/scoped_gate.py"
finish_pr R 6 "$(printf 'bật L3\n\nFreeze-exception: #686')"
expect_blocked "c4. như c3 nhưng commit mang trailer Freeze-exception: #686 ⇒ vẫn exit 8" R 6

# c1 lần nữa với json.py ở cwd (PR kiểm soát được cwd): bộ kiểm chạy `python3 -I`, không import file đó
echo 'open("'"$TMP"'/pwned", "w").write("x")' > "$TMP/R/json.py"
expect_blocked "c1'. json.py ở cwd không chiếm bộ kiểm (python -I): vẫn exit 8" R 2
[ ! -e "$TMP/pwned" ] && ok "c1'. json.py của cwd không được import" || fail "c1'. json.py của cwd đã chạy trong bộ kiểm"
rm -f "$TMP/R/json.py" "$TMP/pwned"

# --- base mới: B on ----------------------------------------------------------------------------------------------------------------
rules_json off off off on 21600 > "$TMP/R/.agents/gate-rules.json"; advance_main R "base: B on"
start_pr R 4; rules_json off off on off 21600 > "$TMP/R/.agents/gate-rules.json"; echo '# l3' > "$TMP/R/universal-agent-devkit/bin/l3_gate.py"; finish_pr R 4
expect_blocked "c2b. bật L3 và hạ B cùng lúc ⇒ exit 8" R 4

start_pr R 7; rules_json off off off off 21600 > "$TMP/R/.agents/gate-rules.json"; echo 'bất kỳ' > "$TMP/R/any-file.txt"; finish_pr R 7
expect_through "off. B on→off kèm file bất kỳ ⇒ đi tiếp" R 7

start_pr R 8; rules_json off off off on 86400 > "$TMP/R/.agents/gate-rules.json"; echo '# c' > "$TMP/R/universal-agent-devkit/bin/suite_cache.py"; finish_pr R 8
expect_through "ttl. TTL 21600→86400 chỉ chạm MANIFEST[CACHE] ⇒ đi tiếp" R 8

start_pr R 9; rules_json off off off on 86400 > "$TMP/R/.agents/gate-rules.json"; echo '# ngoài' > "$TMP/R/universal-agent-devkit/bin/l3_gate.py"; finish_pr R 9
expect_blocked "ttl-. TTL tăng mà chạm ngoài MANIFEST[CACHE] ⇒ exit 8" R 9

rules_json off off off on 86400 > "$TMP/R/.agents/gate-rules.json"; advance_main R "base: TTL 86400"
start_pr R 10; rules_json off off off on 3600 > "$TMP/R/.agents/gate-rules.json"; echo 'bất kỳ' > "$TMP/R/any-file2.txt"; finish_pr R 10
expect_through "ttl. TTL 86400→3600 (hạ) kèm file bất kỳ ⇒ đi tiếp" R 10

start_pr R 11; echo 'không đụng cờ' > "$TMP/R/other.txt"; finish_pr R 11
expect_through "none. PR không đụng gate-rules.json ⇒ đi tiếp, không chạy chốt" R 11

# --- G: base có file cờ nhưng KHÔNG có gate_rules.py (app repo, kit chưa track) -----------------------------------------------------
mkrepo G 0 1
start_pr G 21; rules_json off off on off 21600 > "$TMP/G/.agents/gate-rules.json"; finish_pr G 21
expect_blocked "g1. guard vắng ở BASE mà bật L3 ⇒ exit 8 (đóng, không im lặng cho qua)" G 21
start_pr G 22; rules_json off off off off 3600 > "$TMP/G/.agents/gate-rules.json"; finish_pr G 22
expect_through "g2. guard vắng ở BASE, chỉ hạ/giữ toàn off ⇒ đi tiếp" G 22

# --- N: base không có file cờ, không có guard: PR đầu tiên thêm cờ ------------------------------------------------------------------
mkrepo N 0 0
start_pr N 31; rules_json off off off off 21600 > "$TMP/N/.agents/gate-rules.json"; finish_pr N 31
expect_through "n1. PR đầu thêm gate-rules.json toàn off (guard chưa có ở BASE) ⇒ đi tiếp" N 31
cp "$TMP/run.log" "$TMP/n1.log"
# thêm file cờ lần đầu, mọi luật off ⇒ gate y như khi chưa có file: PR không đụng cờ cho cùng exit code và cùng đầu ra (bỏ số PR)
start_pr N 34; echo 'không đụng cờ' > "$TMP/N/other.txt"; finish_pr N 34
expect_through "n1b. PR không đụng cờ, cùng base (đối chứng cho n1)" N 34
norm() { sed -E 's/#[0-9]+//g; s/[0-9a-f]{40}//g' "$1"; }
[ "$(norm "$TMP/n1.log")" = "$(norm "$TMP/run.log")" ] \
  && ok "n1c. thêm file cờ lần đầu toàn off: đầu ra gate giống hệt PR không có file cờ" \
  || fail "n1c. đầu ra khác nhau: $(diff <(norm "$TMP/n1.log") <(norm "$TMP/run.log") | head -5)"
start_pr N 32; rules_json off off on off 21600 > "$TMP/N/.agents/gate-rules.json"; finish_pr N 32
expect_blocked "n2. PR đầu thêm gate-rules.json mà đã bật L3 ⇒ exit 8" N 32

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_rules_raise: PASS"; exit 0; } || { echo "test_merge_gate_rules_raise: FAIL ($FAILS)"; exit 1; }
