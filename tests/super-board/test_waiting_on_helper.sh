#!/usr/bin/env bash
# Test #601: helper .claude/bin/super-board-waiting-on.py (mark / sweep / migrate) — thẻ chỉ chờ thẻ khác ở Ready với nhãn
# `waiting-on:#N`, không vào Blocked.
#  AC2 sweep: #9 MERGED → gỡ nhãn trên mọi thẻ mang nó; #10 OPEN giữ; #11 không tồn tại không chặn số khác; lỗi tạm thời → exit
#      79 nhưng vẫn gỡ số khác; mỗi N chỉ đọc trạng thái MỘT lần; thẻ Done không bị đụng.
#  AC4 mark: hai lần cùng (I, N) → đúng 1 comment có marker; comment không có dòng bắt đầu bằng `blocked-by:`.
#  AC3 migrate: bỏ qua thẻ có nhãn needs-you/human-gated, thẻ needsYou:true, thẻ trong folded.tsv.
#  AC5 migrate hai lần: lần 2 không ghi gì, trạng thái board cuối giống nhau.
# Chạy offline: gh, super-board-card.sh và super-board-wave-plan.sh là stub ghi mọi lệnh ghi vào $TMP/writes.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/.claude/bin/super-board-waiting-on.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-waiting-on.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/st" "$TMP/inflight/fuse"
printf '{"project":{"owner":"acme","number":1},"repo":{"path":".","remote":"https://github.com/acme/widgets.git"}}' > "$TMP/cfg.json"

# gh stub. Trạng thái số N: $TMP/st/state-N (OPEN|CLOSED|MERGED|ERR|NOTFOUND). Comment của I: $TMP/st/comments-I (mỗi dòng
# một JSON {body}). Ghi nhãn cập nhật luôn $TMP/board.json để mô phỏng board thật.
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB/calls"
case "$*" in *"--repo acme/widgets"*) ;; *) echo "norepo $*" >> "$STUB/calls"; exit 1 ;; esac
if [ "$1 $2" = "label create" ]; then echo "label create $3" >> "$STUB/writes"; exit 0; fi
if [ "$1 $2" = "issue edit" ]; then
  case "$*" in *--add-label*) [ -n "${STUB_FAIL_ADD:-}" ] && { echo "HTTP 502" >&2; exit 1; } ;; esac
  n=$3; shift 3; line="issue edit $n"
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) shift 2 ;;
      --add-label) line="$line --add-label $2"
        jq --argjson n "$n" --arg l "$2" '.items |= map(if .content.number == $n then .labels = (((.labels // []) + [$l]) | unique) else . end)' \
          "$STUB/board.json" > "$STUB/board.tmp" && mv "$STUB/board.tmp" "$STUB/board.json"; shift 2 ;;
      --remove-label) line="$line --remove-label $2"
        jq --argjson n "$n" --arg l "$2" '.items |= map(if .content.number == $n then
            .labels = [(.labels // [])[] | select((if type == "object" then .name else . end | ascii_downcase) != ($l | ascii_downcase))]
            | .content.labels = [(.content.labels // [])[] | select((if type == "object" then .name else . end | ascii_downcase) != ($l | ascii_downcase))]
          else . end)' "$STUB/board.json" > "$STUB/board.tmp" && mv "$STUB/board.tmp" "$STUB/board.json"; shift 2 ;;
      *) shift ;;
    esac
  done
  echo "$line" >> "$STUB/writes"; exit 0
fi
if [ "$1 $2" = "issue comment" ]; then
  n=$3; body=""
  while [ $# -gt 0 ]; do [ "$1" = "--body" ] && body=$2; shift; done
  jq -cn --arg b "$body" '{body: $b}' >> "$STUB/st/comments-$n"
  echo "issue comment $n" >> "$STUB/writes"; exit 0
fi
if [ "$1 $2" = "issue view" ]; then
  case "$*" in
    *"--json comments"*) [ -f "$STUB/st/comments-$3" ] && jq -cs '{comments: .}' "$STUB/st/comments-$3" || echo '{"comments":[]}'; exit 0 ;;
    *"--json state"*)
      echo "$3" >> "$STUB/views"
      s=$(cat "$STUB/st/state-$3" 2>/dev/null || echo OPEN)
      case "$s" in
        ERR) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
        NOTFOUND) echo "GraphQL: Could not resolve to an issue or pull request with the number of $3." >&2; exit 1 ;;
      esac
      # gh thật chỉ in trạng thái trần khi có --jq .state; thiếu --jq thì in JSON
      case "$*" in *"--jq .state"*) echo "$s" ;; *) printf '{"state":"%s"}\n' "$s" ;; esac; exit 0 ;;
  esac
fi
echo "unexpected gh $*" >&2; exit 1
SH
# card.sh stub: items in board.json; move cập nhật board.json.
cat > "$TMP/bin/card.sh" <<'SH'
#!/usr/bin/env bash
[ "$1" = "--config" ] && shift 2
case "$1" in
  items) cat "$STUB/board.json" ;;
  move) echo "move $2 $3" >> "$STUB/writes"
    jq --argjson n "$2" --arg s "$3" '.items |= map(if .content.number == $n then .status = $s else . end)' \
      "$STUB/board.json" > "$STUB/board.tmp" && mv "$STUB/board.tmp" "$STUB/board.json" ;;
  *) exit 64 ;;
esac
SH
# wave-plan stub: pending = thẻ Blocked có openBlockers trong deps.json (không lọc nhãn: helper phải tự lọc needs-you).
cat > "$TMP/bin/wave-plan.sh" <<'SH'
#!/usr/bin/env bash
items=""; while [ $# -gt 0 ]; do [ "$1" = "--items" ] && items=$2; shift; done
jq -c --slurpfile d "$STUB/deps.json" '{cards: [], pending: [.items[] | select(.status == "Blocked")
  | (.content.number | tostring) as $k | select((($d[0][$k].openBlockers) // []) | length > 0)
  | {number: .content.number, title: "t", openBlockers: $d[0][$k].openBlockers}
    + (if $d[0][$k] | has("needsYou") then {needsYou: $d[0][$k].needsYou} else {} end)]}' "$items"
SH
chmod +x "$TMP/bin/"*
export STUB="$TMP" SB_GH="$TMP/bin/gh" SB_CARD="$TMP/bin/card.sh" SB_WAVE_PLAN="$TMP/bin/wave-plan.sh" INFLIGHT_DIR="$TMP/inflight"
helper() { (cd "$TMP" && PYTHONDONTWRITEBYTECODE=1 python3 "$HELPER" "$@" 2> "$TMP/err"); }
reset() { rm -f "$TMP/writes" "$TMP/calls" "$TMP/views" "$TMP/st/"*; : > "$TMP/writes"; : > "$TMP/views"; }
writes() { tr '\n' '|' < "$TMP/writes"; }

# ── AC2 sweep
reset
printf 'MERGED' > "$TMP/st/state-9"; printf 'OPEN' > "$TMP/st/state-10"; printf 'NOTFOUND' > "$TMP/st/state-11"
printf 'ERR' > "$TMP/st/state-12"; printf 'CLOSED' > "$TMP/st/state-13"
cat > "$TMP/board.json" <<'J'
{"items":[
 {"id":"I20","status":"Ready","labels":["bug","waiting-on:#9"],"content":{"type":"Issue","number":20}},
 {"id":"I21","status":"Ready","labels":["waiting-on:#10"],"content":{"type":"Issue","number":21,"labels":[{"name":"Waiting-On:#9"}]}},
 {"id":"I22","status":"Ready","labels":["waiting-on:#11"],"content":{"type":"Issue","number":22}},
 {"id":"I23","status":"Ready","labels":["waiting-on:#12"],"content":{"type":"Issue","number":23}},
 {"id":"I24","status":"Done","labels":["waiting-on:#9"],"content":{"type":"Issue","number":24}},
 {"id":"I25","status":"Ready","labels":null,"content":{"type":"Issue","number":25,"labels":null}},
 {"id":"I26","status":"Ready","labels":["waiting-on:#13","waiting-on:#x"],"content":{"type":"Issue","number":26}}]}
J
rc=0; OUT=$(helper sweep --config "$TMP/cfg.json") || rc=$?
[ "$rc" -eq 79 ] && ok "sweep: a transient read error on #12 ends with exit 79" || fail "sweep exit $rc (want 79): $(cat "$TMP/err")"
grep -qx "issue edit 20 --remove-label waiting-on:#9" "$TMP/writes" && grep -qix "issue edit 21 --remove-label waiting-on:#9" "$TMP/writes" \
  && ok "sweep: #9 MERGED → label removed on both cards that carry it (#20 and #21, label in content.labels)" \
  || fail "sweep #9 removal: $(writes)"
grep -q "issue edit 24 " "$TMP/writes" && fail "sweep touched Done card #24: $(writes)" || ok "sweep: a Done card is not touched"
grep -q "remove-label waiting-on:#10\|remove-label waiting-on:#11\|remove-label waiting-on:#12" "$TMP/writes" \
  && fail "sweep removed a label it must keep: $(writes)" || ok "sweep: #10 OPEN, #11 not found and #12 unreadable keep their labels"
grep -qx "issue edit 26 --remove-label waiting-on:#13" "$TMP/writes" \
  && ok "sweep: #13 CLOSED is still removed after the #11/#12 errors" || fail "sweep #13 not removed: $(writes)"
dup=$(sort "$TMP/views" | uniq -d | tr '\n' ' '); nv=$(sort -u "$TMP/views" | tr '\n' ' ')
[ -z "$dup" ] && [ "$nv" = "10 11 12 13 9 " ] && ok "sweep: each number is read exactly once (9..13)" || fail "sweep reads: dup=[$dup] set=[$nv]"
echo "$OUT" | jq -e '(.removed | sort) == [[20,9],[21,9],[26,13]] and ([.kept[] | tostring] | index("[21,10]") != null)
    and ([.errors[].n] | sort) == [11,12]' >/dev/null 2>&1 \
  && ok "sweep: JSON lists removed, kept and errors" || fail "sweep JSON: $OUT"
grep -q "^norepo" "$TMP/calls" && fail "a gh call without --repo acme/widgets: $(grep norepo "$TMP/calls" | head -1)" \
  || ok "sweep: every gh call carries --repo acme/widgets"
# không có lỗi tạm thời: số không tồn tại không làm exit ≠ 0
reset
printf 'MERGED' > "$TMP/st/state-9"; printf 'NOTFOUND' > "$TMP/st/state-11"
cat > "$TMP/board.json" <<'J'
{"items":[
 {"id":"I20","status":"Ready","labels":["waiting-on:#9"],"content":{"type":"Issue","number":20}},
 {"id":"I22","status":"Ready","labels":["waiting-on:#11"],"content":{"type":"Issue","number":22}}]}
J
rc=0; OUT=$(helper sweep --config "$TMP/cfg.json") || rc=$?
[ "$rc" -eq 0 ] && grep -qx "issue edit 20 --remove-label waiting-on:#9" "$TMP/writes" \
  && ok "sweep: an unknown #11 does not block #9 and exits 0" || fail "sweep with unknown #11: exit $rc, $(writes) $(cat "$TMP/err")"

# ── AC4 mark
reset
rc=0; O1=$(helper mark --config "$TMP/cfg.json" --issue 30 --on 10,9,9 --why "$(printf 'x\nblocked-by: 5')") || rc=$?
rc2=0; O2=$(helper mark --config "$TMP/cfg.json" --issue 30 --on 9,10) || rc2=$?
[ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && ok "mark: exit 0 twice" || fail "mark exits $rc/$rc2: $(cat "$TMP/err")"
[ "$(wc -l < "$TMP/st/comments-30" 2>/dev/null | tr -d ' ')" = "1" ] && ok "mark: two marks of (#30, 9+10) leave exactly one comment" \
  || fail "mark comments on #30: $(cat "$TMP/st/comments-30" 2>/dev/null | wc -l)"
echo "$O1" | jq -e '.issue == 30 and .labels == ["waiting-on:#9","waiting-on:#10"] and .commented == true' >/dev/null 2>&1 \
  && echo "$O2" | jq -e '.commented == false' >/dev/null 2>&1 && ok "mark: JSON {issue, labels, commented} true then false" || fail "mark JSON: $O1 / $O2"
BODY=$(jq -r .body "$TMP/st/comments-30" 2>/dev/null)
printf '%s\n' "$BODY" | grep -qF '<!-- sb-waiting-on 30:9,10 -->' && ok "mark: comment carries the marker <!-- sb-waiting-on 30:9,10 -->" \
  || fail "mark marker missing: $BODY"
printf '%s\n' "$BODY" | grep -qi '^[[:space:]]*blocked-by:' && fail "mark comment has a blocked-by: line: $BODY" \
  || ok "mark: no comment line starts with blocked-by: (even with a multi-line --why)"
printf '%s\n' "$BODY" | head -1 | grep -qF '[orchestrator] [report] ⏳ waiting · on #9, #10' && ok "mark: comment header names #9, #10" \
  || fail "mark header: $(printf '%s\n' "$BODY" | head -1)"
grep -qx "label create waiting-on:#9" "$TMP/writes" && grep -qx "issue edit 30 --add-label waiting-on:#9 --add-label waiting-on:#10" "$TMP/writes" \
  && ok "mark: creates the labels and adds both to #30" || fail "mark writes: $(writes)"
rc=0; helper mark --config "$TMP/cfg.json" --issue 30 --on abc >/dev/null || rc=$?
rc2=0; helper mark --config "$TMP/cfg.json" --issue 30 >/dev/null || rc2=$?
[ "$rc" -eq 64 ] && [ "$rc2" -eq 64 ] && ok "mark: bad --on / missing --on exit 64" || fail "mark bad args exit $rc/$rc2"

# ── AC3 + AC5 migrate
reset
cat > "$TMP/board.json" <<'J'
{"items":[
 {"id":"I40","status":"Blocked","labels":["bug","⏳ chờ thẻ khác"],"content":{"type":"Issue","number":40}},
 {"id":"I41","status":"Blocked","labels":["needs-you","loop:rebase"],"content":{"type":"Issue","number":41}},
 {"id":"I42","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":42}},
 {"id":"I43","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":43}},
 {"id":"I44","status":"Blocked","labels":null,"content":{"type":"Issue","number":44,"labels":[{"name":"Human-Gated"}]}},
 {"id":"I45","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":45}}]}
J
printf '{"40":{"openBlockers":[9]},"41":{"openBlockers":[9]},"42":{"openBlockers":[9],"needsYou":true},"43":{"openBlockers":[9]},"44":{"openBlockers":[9]}}' > "$TMP/deps.json"
printf '43\n' > "$TMP/inflight/fuse/folded.tsv"
cp "$TMP/board.json" "$TMP/board.orig"
rc=0; OUT=$(helper migrate --config "$TMP/cfg.json" --dry-run) || rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$TMP/writes" ] && echo "$OUT" | jq -e '.migrated == [40]' >/dev/null 2>&1 \
  && ok "migrate --dry-run: reports #40, writes nothing" || fail "migrate --dry-run: exit $rc, $OUT, $(writes) $(cat "$TMP/err")"
rc=0; OUT=$(helper migrate --config "$TMP/cfg.json") || rc=$?
[ "$rc" -eq 0 ] && echo "$OUT" | jq -e '.migrated == [40] and ([.skipped[].number] | sort) == [41,42,43,44]' >/dev/null 2>&1 \
  && ok "migrate: only #40 migrates; #41 needs-you, #42 needsYou, #43 folded, #44 human-gated are skipped" || fail "migrate: exit $rc, $OUT $(cat "$TMP/err")"
grep -q "issue edit 4[1-4] \|move 4[1-4] \|comment 4[1-4]" "$TMP/writes" && fail "migrate wrote to a skipped card: $(writes)" \
  || ok "migrate: no write touches #41-#44"
grep -qx "move 40 Ready" "$TMP/writes" && grep -qx "issue edit 40 --add-label waiting-on:#9" "$TMP/writes" \
  && grep -qx "issue edit 40 --remove-label ⏳ chờ thẻ khác" "$TMP/writes" && grep -qx "issue comment 40" "$TMP/writes" \
  && ok "migrate: #40 gets waiting-on:#9 + one comment, loses ⏳ chờ thẻ khác, moves to Ready" || fail "migrate #40 writes: $(writes)"
jq -e '.items[] | select(.content.number == 40) | .status == "Ready" and (.labels | index("waiting-on:#9")) != null' "$TMP/board.json" >/dev/null 2>&1 \
  && ok "migrate: board shows #40 in Ready with waiting-on:#9" || fail "board after migrate: $(jq -c '.items[0]' "$TMP/board.json")"
cp "$TMP/board.json" "$TMP/board.after1"; : > "$TMP/writes"
rc=0; OUT=$(helper migrate --config "$TMP/cfg.json") || rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$TMP/writes" ] && ok "migrate twice: the second run writes nothing" || fail "migrate 2nd run: exit $rc, $(writes)"
cmp -s "$TMP/board.json" "$TMP/board.after1" && ok "migrate twice: the board state is the same after both runs" || fail "board changed on the 2nd run"
[ "$(wc -l < "$TMP/st/comments-40" | tr -d ' ')" = "1" ] && ok "migrate twice: #40 has one comment" || fail "#40 comments: $(wc -l < "$TMP/st/comments-40")"

# ── Audit 1: lệnh con không được ghi file halt DÙNG CHUNG (card.sh/deps.sh chạy SB_GITHUB_READ_STRICT=1: một lần đọc hỏng ghi
# halt → dừng cả board). Mỗi lệnh con nhận SB_GITHUB_HALT_FILE riêng, xoá sau khi chạy.
cat > "$TMP/bin/card-halt.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${SB_GITHUB_HALT_FILE:-}" >> "$STUB/halt-seen"
[ -n "${SB_GITHUB_HALT_FILE:-}" ] && echo '{"operation":"project item-list"}' > "$SB_GITHUB_HALT_FILE"
echo "github read halted" >&2; exit 79
SH
# card.sh chậm: con cháu `sleep` giữ pipe stdout; timeout phải giết cả nhóm tiến trình
cat > "$TMP/bin/card-slow.sh" <<'SH'
#!/usr/bin/env bash
sleep 8 &
echo $! > "$STUB/slowpid"
wait
SH
chmod +x "$TMP/bin/card-halt.sh" "$TMP/bin/card-slow.sh"
reset; rm -f "$TMP/halt-seen" "$TMP/real-halt.json"
cp "$TMP/board.orig" "$TMP/board.json"
rc=0; SB_GITHUB_HALT_FILE="$TMP/real-halt.json" SB_CARD="$TMP/bin/card-halt.sh" helper sweep --config "$TMP/cfg.json" >/dev/null || rc=$?
seen=$(head -1 "$TMP/halt-seen" 2>/dev/null)
[ "$rc" -eq 79 ] && [ ! -e "$TMP/real-halt.json" ] && [ -n "$seen" ] && [ "$seen" != "$TMP/real-halt.json" ] && [ ! -e "$seen" ] \
  && ok "audit1 sweep: card.sh writing a halt → exit 79, the shared halt file is NOT created, the private one is removed" \
  || fail "audit1 halt isolation: rc=$rc real=$(ls "$TMP/real-halt.json" 2>/dev/null) seen=[$seen] exists=$([ -n "$seen" ] && [ -e "$seen" ] && echo y)"
rc=0; SB_GITHUB_HALT_FILE="$TMP/real-halt.json" SB_CARD="$TMP/bin/card-halt.sh" helper migrate --config "$TMP/cfg.json" >/dev/null || rc=$?
[ "$rc" -eq 79 ] && [ ! -e "$TMP/real-halt.json" ] && ok "audit1 migrate: same, shared halt file untouched" \
  || fail "audit1 migrate halt: rc=$rc real=$(ls "$TMP/real-halt.json" 2>/dev/null)"
rm -f "$TMP/slowpid"; t0=$(date +%s)
rc=0; SB_WAITING_ON_TIMEOUT=1 SB_CARD="$TMP/bin/card-slow.sh" helper sweep --config "$TMP/cfg.json" >/dev/null || rc=$?
dt=$(( $(date +%s) - t0 )); spid=$(cat "$TMP/slowpid" 2>/dev/null)
sleep 0.3
alive=no; [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null && alive=yes
[ "$rc" -eq 79 ] && [ "$dt" -lt 5 ] && [ "$alive" = no ] \
  && ok "audit1 timeout: the whole process group is killed (exit 79 in ${dt}s, grandchild sleep gone)" \
  || fail "audit1 timeout: rc=$rc took ${dt}s grandchild alive=$alive"
[ -n "$spid" ] && kill "$spid" 2>/dev/null

# ── Audit 1: --items <file> — runner truyền sẵn board đã đọc; case dưới kiểm lời gọi `card.sh items` qua $STUB/card-items-calls
cat > "$TMP/bin/card-noitems.sh" <<'SH'
#!/usr/bin/env bash
[ "$1" = "--config" ] && shift 2
case "$1" in
  items) echo "items" >> "$STUB/card-items-calls"; exit 69 ;;
  *) exec bash "$STUB/bin/card.sh" "$@" ;;
esac
SH
chmod +x "$TMP/bin/card-noitems.sh"
reset; rm -f "$TMP/card-items-calls"
printf 'CLOSED' > "$TMP/st/state-9"
printf '{"items":[{"id":"I20","status":"Ready","labels":["waiting-on:#9"],"content":{"type":"Issue","number":20}}]}' > "$TMP/board.json"
cp "$TMP/board.json" "$TMP/items.json"
rc=0; OUT=$(SB_CARD="$TMP/bin/card-noitems.sh" helper sweep --config "$TMP/cfg.json" --items "$TMP/items.json") || rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$TMP/card-items-calls" ] && grep -qx "issue edit 20 --remove-label waiting-on:#9" "$TMP/writes" \
  && ok "audit1 sweep --items: reads the given file, no card.sh items call" || fail "sweep --items: rc=$rc $(writes) $(cat "$TMP/err")"
reset; rm -f "$TMP/card-items-calls"
printf '{"items":[{"id":"I40","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":40}}]}' > "$TMP/board.json"
cp "$TMP/board.json" "$TMP/items.json"; printf '{"40":{"openBlockers":[9]}}' > "$TMP/deps.json"; : > "$TMP/inflight/fuse/folded.tsv"
rc=0; OUT=$(SB_CARD="$TMP/bin/card-noitems.sh" helper migrate --config "$TMP/cfg.json" --items "$TMP/items.json") || rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$TMP/card-items-calls" ] && echo "$OUT" | jq -e '.migrated == [40]' >/dev/null 2>&1 && grep -qx "move 40 Ready" "$TMP/writes" \
  && ok "audit1 migrate --items: reads the given file, no card.sh items call" || fail "migrate --items: rc=$rc $OUT $(cat "$TMP/err")"
rc=0; helper sweep --config "$TMP/cfg.json" --items "$TMP/nope.json" >/dev/null || rc=$?
[ "$rc" -eq 79 ] && ok "audit1 --items unreadable file → exit 79" || fail "--items missing file exit $rc"

# ── Audit 2: mark tự kiểm trạng thái từng N TRƯỚC mọi lần ghi
reset; printf 'CLOSED' > "$TMP/st/state-8"; printf 'OPEN' > "$TMP/st/state-9"
rc=0; OUT=$(helper mark --config "$TMP/cfg.json" --issue 31 --on 8,9) || rc=$?
[ "$rc" -eq 0 ] && echo "$OUT" | jq -e '.labels == ["waiting-on:#9"]' >/dev/null 2>&1 && ! grep -q "#8" "$TMP/writes" \
  && grep -qx "issue edit 31 --add-label waiting-on:#9" "$TMP/writes" && grep -qF '<!-- sb-waiting-on 31:9 -->' "$TMP/st/comments-31" \
  && ok "audit2 mark #8 CLOSED + #9 OPEN → only waiting-on:#9 (label, comment marker 31:9)" || fail "mark closed+open: rc=$rc $OUT $(writes) $(cat "$TMP/err")"
reset; printf 'CLOSED' > "$TMP/st/state-8"; printf 'MERGED' > "$TMP/st/state-9"
rc=0; OUT=$(helper mark --config "$TMP/cfg.json" --issue 31 --on 8,9) || rc=$?
[ "$rc" -eq 0 ] && echo "$OUT" | jq -e '.labels == [] and .commented == false' >/dev/null 2>&1 && [ ! -s "$TMP/writes" ] \
  && ok "audit2 mark: every N closed → labels=[], exit 0, nothing written" || fail "mark all closed: rc=$rc $OUT $(writes)"
reset; printf 'OPEN' > "$TMP/st/state-8"; printf 'ERR' > "$TMP/st/state-9"
rc=0; helper mark --config "$TMP/cfg.json" --issue 31 --on 8,9 >/dev/null || rc=$?
[ "$rc" -eq 79 ] && [ ! -s "$TMP/writes" ] && ok "audit2 mark: transient read error → exit 79 before any write" || fail "mark read error: rc=$rc $(writes)"
reset; printf 'NOTFOUND' > "$TMP/st/state-9"
rc=0; helper mark --config "$TMP/cfg.json" --issue 31 --on 9 >/dev/null || rc=$?
[ "$rc" -eq 64 ] && [ ! -s "$TMP/writes" ] && ok "audit2 mark: unknown #9 → exit 64, nothing written" || fail "mark unknown: rc=$rc $(writes)"

# ── Audit 3: thứ tự ghi — tạo nhãn, comment (một lần, marker), CUỐI CÙNG add-label. add-label hỏng → lần sau chỉ gắn nhãn.
reset
rc=0; STUB_FAIL_ADD=1 helper mark --config "$TMP/cfg.json" --issue 32 --on 9 >/dev/null || rc=$?
[ "$rc" -eq 69 ] && [ "$(wc -l < "$TMP/st/comments-32" 2>/dev/null | tr -d ' ')" = "1" ] \
  && ok "audit3 add-label fails → exit 69, the comment is already there" || fail "add-label fail: rc=$rc comments=$(wc -l < "$TMP/st/comments-32" 2>/dev/null)"
order=$(grep -n "" "$TMP/writes" | tr '\n' '|')
case "$order" in *"label create waiting-on:#9|"*"issue comment 32|"*) ok "audit3 order: label create, then comment, add-label last" ;; *) fail "audit3 order: $order" ;; esac
: > "$TMP/writes"
rc=0; OUT=$(helper mark --config "$TMP/cfg.json" --issue 32 --on 9) || rc=$?
[ "$rc" -eq 0 ] && [ "$(wc -l < "$TMP/st/comments-32" | tr -d ' ')" = "1" ] && grep -qx "issue edit 32 --add-label waiting-on:#9" "$TMP/writes" \
  && ! grep -q "issue comment" "$TMP/writes" && echo "$OUT" | jq -e '.commented == false' >/dev/null 2>&1 \
  && ok "audit3 retry: no second comment, only the label is added" || fail "audit3 retry: rc=$rc $(writes) $OUT"

# ── Audit 4: folded.tsv đọc ở main checkout dùng chung (INFLIGHT_DIR env > .repo.path tuyệt đối > cha của git-common-dir)
reset
printf '{"items":[{"id":"I40","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":40}}]}' > "$TMP/board.json"
printf '{"40":{"openBlockers":[9]}}' > "$TMP/deps.json"
mkdir -p "$TMP/main/.claude/super-board/inflight/fuse"; printf '40\tREG-X\n' > "$TMP/main/.claude/super-board/inflight/fuse/folded.tsv"
printf '{"project":{"owner":"acme","number":1},"repo":{"path":"%s","remote":"https://github.com/acme/widgets.git"}}' "$TMP/main" > "$TMP/cfg-abs.json"
rc=0; OUT=$(cd "$TMP" && env -u INFLIGHT_DIR PYTHONDONTWRITEBYTECODE=1 python3 "$HELPER" migrate --config "$TMP/cfg-abs.json" --dry-run 2>"$TMP/err") || rc=$?
[ "$rc" -eq 0 ] && echo "$OUT" | jq -e '.migrated == [] and .skipped[0].why == "folded by the suite fuse"' >/dev/null 2>&1 \
  && ok "audit4 folded.tsv read from the absolute .repo.path checkout" || fail "audit4 repo.path: rc=$rc $OUT $(cat "$TMP/err")"
# một worktree: --show-toplevel là worktree, folded.tsv dùng chung nằm ở main checkout (cha của --git-common-dir). Stub VCS trên
# PATH trả bố cục worktree (không tạo repo thật trong test).
GR="$TMP/gr"; mkdir -p "$GR/.claude/super-board/inflight/fuse" "$TMP/gr-wt" "$TMP/vcs"
printf '40\n' > "$GR/.claude/super-board/inflight/fuse/folded.tsv"
cat > "$TMP/vcs/git" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --git-common-dir") echo "$STUB/gr/.git" ;;
  "rev-parse --show-toplevel") echo "$STUB/gr-wt" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/vcs/git"
rc=0; OUT=$(cd "$TMP/gr-wt" && env -u INFLIGHT_DIR PATH="$TMP/vcs:$PATH" PYTHONDONTWRITEBYTECODE=1 python3 "$HELPER" migrate --config "$TMP/cfg.json" --dry-run 2>"$TMP/err") || rc=$?
[ "$rc" -eq 0 ] && echo "$OUT" | jq -e '.migrated == [] and .skipped[0].why == "folded by the suite fuse"' >/dev/null 2>&1 \
  && ok "audit4 run from a worktree: folded.tsv read from the main checkout (parent of --git-common-dir)" || fail "audit4 worktree: rc=$rc $OUT $(cat "$TMP/err")"
mkdir -p "$TMP/inf-bad/fuse/folded.tsv"   # thư mục thay vì file: lỗi đọc khác FileNotFoundError
rc=0; INFLIGHT_DIR="$TMP/inf-bad" helper migrate --config "$TMP/cfg.json" --dry-run >/dev/null || rc=$?
[ "$rc" -eq 79 ] && ok "audit4 unreadable folded.tsv (not missing) → exit 79" || fail "audit4 unreadable folded.tsv exit $rc"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
