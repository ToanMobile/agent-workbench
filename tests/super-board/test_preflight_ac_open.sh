#!/usr/bin/env bash
# T0054 (24/10): thẻ mang nhãn ac-open (PR của chính nó đã merge nhưng còn AC chưa chứng minh, merge gate mở lại) không được
# preflight giữ lại là "already delivered" chỉ vì PR vừa merge có tiêu đề giống thẻ. Không nhãn: vẫn hold done như cũ.
# gh giả, offline. SB_PREFLIGHT=<file> chạy bản cũ để thấy ĐỎ.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="${SB_PREFLIGHT:-$ROOT/.claude/bin/super-board-preflight.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-acopen.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}' ;;
  *" pr list "*"merged"*) echo '[{"number":90,"title":"⚡ [perf] gate: cache REG-DK-ALL-01 và chạy hết khi đã bắt đầu","body":"Refs #77","url":"u"}]' ;;
  *" pr list "*|*" issue list "*) echo '[]' ;;
  *" issue view "*) printf '{"number":77,"title":"⚡ [perf] gate: cache REG-DK-ALL-01 và chạy hết khi đã bắt đầu","body":"## Acceptance Criteria\\n- [ ] a\\n","labels":%s}\n' "$LABELS" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GH_GUARD_STATE_FILE="$TMP/budget"

out=$(LABELS='[{"name":"feature"}]' bash "$PREFLIGHT" --repo o/r --issues 77 2>"$TMP/err")
[ "$(printf '%s' "$out" | jq -r '."77".tag')" = done ] && ok "không nhãn: PR merged giống tiêu đề → hold done (như cũ)" \
  || fail "no label: $out $(cat "$TMP/err")"
out=$(LABELS='[{"name":"feature"},{"name":"ac-open"}]' bash "$PREFLIGHT" --repo o/r --issues 77 2>"$TMP/err")
[ "$(printf '%s' "$out" | jq -r '."77".verdict')" = proceed ] && ok "nhãn ac-open: không coi là đã giao → proceed" \
  || fail "ac-open: $out $(cat "$TMP/err")"

[ "$FAILS" -eq 0 ] && { echo "preflight ac-open: all checks passed"; exit 0; }
echo "preflight ac-open: $FAILS FAILED"; exit 1
