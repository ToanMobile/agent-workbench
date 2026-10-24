#!/usr/bin/env bash
# Test hồi quy câu hỏi 5 "quá lớn" của .claude/bin/super-board-preflight.sh với `gh` giả (offline).
# 2026-10-18/19: NFH #4, #13, #14, #54 và OfficeReader #98, #102 lên Ready, builder tốn một lượt rồi chặn ❓ "quá lớn";
# script trả `proceed` vì chỉ hỏi 4 câu (trùng, đang làm, chồng file, thiếu AC). Fixture là body thật của các thẻ đó
# (lấy bằng `gh issue view`), cùng 4 thẻ đã build bình thường giống chúng nhất (phải `proceed`).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT="$ROOT/.claude/bin/super-board-preflight.sh"
FIX="$ROOT/tests/super-board/fixtures/preflight-too-big"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-preflight-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh giả: hạn mức rộng, không PR/issue đóng nào (để chỉ câu hỏi 5 quyết định), `issue view` đọc fixture theo repo + số.
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}' ;;
  *" api graphql "*) exit 1 ;;
  *" pr list "*|*" issue list "*) echo '[]' ;;
  *" issue view "*)
    n=""; repo=""; prev=""
    for a in "$@"; do
      [ "$prev" = view ] && n="$a"
      [ "$prev" = --repo ] && repo="$a"
      prev="$a"
    done
    cat "$SB_FIXTURES/${repo##*/}-$n.json" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_FIXTURES="$FIX" \
  SB_GH_GUARD_STATE_FILE="$TMP/budget"

# Một lần gọi cho cả lô của mỗi repo, như wave và lint gọi.
for spec in Neighbours-From-Hell:4,13,14,15,16,24,47,54 OfficeReader:94,98,102 GeelyEx2:11 Synthetic:901,902,903,904,905,906,907,908,909,910,911,912; do
  repo="${spec%%:*}"
  bash "$PREFLIGHT" --repo "ToanMobile/$repo" --issues "${spec##*:}" >"$TMP/$repo.json" 2>"$TMP/$repo.err" \
    || fail "$repo: preflight exit $? ($(tail -1 "$TMP/$repo.err"))"
done

verdict() { jq -r --arg n "$2" '.[$n] | "\(.verdict)/\(.tag)"' "$TMP/$1.json" 2>/dev/null; }

# 908 là AC "OOM" mà Risk ghi "không cần máy thật" (phủ định không tính là tín hiệu máy thật).
# Ca biên: #16 Fix đúng 5 đầu việc ngắn + "Giai đoạn"; #15 chỉ "Giai đoạn" + AC cần số liệu vận hành; 905 là
# body #13 xuống dòng CRLF; 906 là #98 với tiêu đề "## Acceptance Criteria (…)" (has_acs và sect phải cùng nhận);
# 909 là AC "Không OOM trên máy thật" (AC luôn là tín hiệu, phủ định chỉ lọc ở Risk); 910 là Risk có một dòng phủ định
# và một dòng cần máy thật; 911 là phủ định cách cụm máy thật bởi dấu phẩy ("Không tái hiện được …, cần máy thật");
# 912 là một dòng vừa phủ định vừa cần máy thật. Cả bốn phải bị giữ.
# 907 là #16 thêm mục "## Fixtures" cuối body (không được thay mục Fix).
# Gợi ý tách phải có ít nhất một dòng riêng của thẻ, không chỉ câu mặc định.
for spec in Neighbours-From-Hell:4 Neighbours-From-Hell:13 Neighbours-From-Hell:14 Neighbours-From-Hell:15 \
            Neighbours-From-Hell:16 Neighbours-From-Hell:54 OfficeReader:98 OfficeReader:102 Synthetic:905 \
            Synthetic:906 Synthetic:907 Synthetic:909 Synthetic:910 Synthetic:911 Synthetic:912; do
  repo="${spec%%:*}"; n="${spec##*:}"; got=$(verdict "$repo" "$n")
  if [ "$got" = hold/too-big ] \
     && jq -e --arg n "$n" '.[$n] | (.evidence | length) > 0 and (.reason | test("too big"))
          and any(.split[]; test("^vertical slices") | not)' \
          "$TMP/$repo.json" >/dev/null; then
    ok "$repo #$n: hold/too-big, có bằng chứng và gợi ý tách"
  else
    fail "$repo #$n: muốn hold/too-big kèm evidence + split, được $got"
  fi
done

# Thẻ đã build xong, giống thẻ quá lớn nhất: Risk "máy thật" (#94), đo trên xe (Geely #11), "đụng nhiều file" (#24),
# Fix nhiều gạch đầu dòng + 4 vùng (#47). Ca tổng hợp: AC "OOM" mà thẻ không ghi máy thật (901), đúng một tín hiệu
# là tiêu đề nêu 3 thứ (902), đúng một tín hiệu và sát ngưỡng ở mọi tín hiệu khác: Fix 4 việc, 3 vùng, tiêu đề
# 2 việc (904). Không được giữ nhầm.
for spec in OfficeReader:94 GeelyEx2:11 Neighbours-From-Hell:24 Neighbours-From-Hell:47 Synthetic:901 Synthetic:902 \
            Synthetic:904 Synthetic:908; do
  repo="${spec%%:*}"; n="${spec##*:}"; got=$(verdict "$repo" "$n")
  [ "$got" = proceed/clean ] && ok "$repo #$n: proceed (thẻ bình thường không bị giữ)" \
    || fail "$repo #$n: muốn proceed/clean, được $got"
done

# Thứ tự: thẻ thiếu AC báo "unclear" trước, dù cũng quá lớn (903).
got=$(verdict Synthetic 903)
[ "$got" = hold/unclear ] && ok "Synthetic #903: thiếu AC báo unclear trước too-big" || fail "Synthetic #903: muốn hold/unclear, được $got"

# 24/10 (người dùng: "gom lại nhiều nhất có thể, đỡ chạy gate nhiều lần"): board không có trần dòng merge
# (merge_policy.auto_max_lines = 0, --cap 0) thì không giữ thẻ vì nhiều việc: một thẻ = một PR = một gate.
# Tín hiệu agent không tự làm được (máy thật, người thật) vẫn giữ.
bash "$PREFLIGHT" --repo ToanMobile/Neighbours-From-Hell --issues 16 --cap 0 >"$TMP/cap0.json" 2>"$TMP/cap0.err" \
  || fail "--cap 0: preflight exit $? ($(tail -1 "$TMP/cap0.err"))"
got=$(jq -r '.["16"] | "\(.verdict)/\(.tag)"' "$TMP/cap0.json" 2>/dev/null)
[ "$got" = proceed/clean ] && ok "--cap 0: thẻ nhiều việc (#16) proceed, không đòi tách" || fail "--cap 0 #16: muốn proceed/clean, được $got"
bash "$PREFLIGHT" --repo ToanMobile/Synthetic --issues 909 --cap 0 >"$TMP/cap0d.json" 2>/dev/null
got=$(jq -r '.["909"] | "\(.verdict)/\(.tag)"' "$TMP/cap0d.json" 2>/dev/null)
[ "$got" = hold/too-big ] && ok "--cap 0: AC cần máy thật (#909) vẫn hold" || fail "--cap 0 #909: muốn hold/too-big, được $got"
jq -e '.["909"] | (.reason | test("merge cap") | not) and (.split | all(test("vertical slices") | not))' "$TMP/cap0d.json" >/dev/null \
  && ok "--cap 0: lý do và gợi ý không nhắc trần dòng hay tách lát" || fail "--cap 0 #909: $(jq -c '.["909"] | {reason, split}' "$TMP/cap0d.json")"
bash "$PREFLIGHT" --repo ToanMobile/Neighbours-From-Hell --issues 16 --cap 300 >"$TMP/cap300.json" 2>/dev/null
jq -e '.["16"] | (.evidence | any(test("300-line"))) and (.evidence | all(test("400-line") | not))' "$TMP/cap300.json" >/dev/null \
  && ok "--cap 300: thông điệp nói đúng trần 300" || fail "--cap 300: $(jq -c '.["16"].evidence' "$TMP/cap300.json")"

# Trần lớn (--cap 2000): 5 việc ngắn (~500 dòng) dưới trần thì tín hiệu "nhiều việc ở Fix" không tính (trần thật trong
# thông điệp được kiểm ở ca --cap 300 phía trên).
bash "$PREFLIGHT" --repo ToanMobile/Neighbours-From-Hell --issues 16 --cap 2000 >"$TMP/cap2k.json" 2>/dev/null
jq -e '.["16"] | (.evidence | any(test("separate deliverables")) | not)' "$TMP/cap2k.json" >/dev/null \
  && ok "--cap 2000: Fix 5 việc (~500 dòng) dưới trần không còn là tín hiệu" || fail "--cap 2000: vẫn tính Fix 5 việc"
bash "$PREFLIGHT" --repo ToanMobile/Neighbours-From-Hell --issues 16 --cap abc >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && ok "--cap không phải số: exit 64" || fail "--cap abc: exit $rc (muốn 64)"

[ "$FAILS" -eq 0 ] && echo "PASS: preflight too-big" || { echo "FAIL: $FAILS ca"; exit 1; }
