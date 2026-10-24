#!/usr/bin/env bash
# super-board-preflight.sh — before a card goes Ready → Building, is it worth building?
#
# Five questions, asked of every candidate card before any Builder starts:
#
#   1. Already done?        a merged PR closes it, or a merged PR / closed issue carries
#                           the same fingerprint or (near-)same title.
#   2. Already in progress? an open PR from ANOTHER branch closes it or has the same
#                           title, or another card in Building/QA/Review (or a lower-
#                           numbered Ready peer in this wave) has the same title.
#   3. File overlap?        an open PR touches files this card names, or a lower-numbered
#                           card in the same --issues batch names them. Not a duplicate —
#                           a sequencing problem. The card goes behind the issue that
#                           PR closes (blocked-by, so the wave-start sweep frees it when
#                           that issue closes), or, if the PR closes nothing, proceeds
#                           with an expected-conflict note so the merge gate rebases. Two
#                           batch peers: the lower number proceeds, the other is sequenced
#                           `blockedBy: [<lower>]` — never both against each other.
#   4. Unclear?             no `## Acceptance Criteria` section with at least one item (`-`, `*`, `1)` or `1.`).
#   5. Too big?             (lint.md tiêu chí 15) ≥2 tín hiệu cỡ lớn trong chính nội dung issue:
#                           Fix liệt kê ≥5 đầu việc ngắn (≈100 dòng mỗi việc, vượt trần 400 dòng)
#                           hoặc tiêu đề nêu ≥3 việc · trải ≥4 vùng · thẻ tự nhận lớn (giai đoạn,
#                           vertical slice, "nhiều thành phần") · phạm vi là cả một mục spec · AC
#                           cần người thật hoặc số liệu vận hành. AC chỉ máy thật chứng minh được
#                           (OOM, FPS, bộ nhớ) trên thẻ ghi "máy thật" tính 2. Hỏi trước câu 3:
#                           thẻ phải tách thì chờ tách, không chờ PR.
#
# Outcomes: proceed · hold (dup done / dup in progress / unclear / too big) · sequence.
#
# THIS SCRIPT IS THE MECHANICAL HALF. It catches what string matching can catch and
# lists near-misses (`candidates`) for the pre-flight sub-agent, which makes the
# semantic call: "same feature, different words" and "AC contradicts the code" are
# judgements, not regexes. The agent may upgrade proceed → hold on evidence; it may
# downgrade a mechanical hold only by naming why the match is a different feature.
#
# Cheap by construction: the three list calls run ONCE per invocation however many
# issues are checked (pass --issues 12,14,15 to batch a wave), plus one `gh issue
# view` per issue. The worker gh guard runs first when it is installed alongside.
#
# Usage:
#   super-board-preflight.sh --repo <owner/name> --issues <N[,M…]>
#                            [--inflight <cards.json>]   # [{number,title,status}] board cards
#                            [--files a/b.ts,c/d.ts]     # paths the card will touch (else: parsed from body)
#                            [--threshold 0.6]           # title Jaccard for a duplicate
#                            [--cap 400]                 # merge_policy.auto_max_lines; 0 = no line cap: a card with many
#                                                        # deliverables is one PR (one gate), never held as too big
#
# Stdout, one object keyed by issue number:
#   { "14": { "number": 14, "title": "…", "verdict": "proceed|hold|sequence",
#             "tag": "done|in-progress|unclear|too-big|overlap|clean", "reason": "…",
#             "evidence": ["#31 merged: Resolves #14"], "blockedBy": [31],
#             "conflictWith": [52], "candidates": [{"ref":"#40","kind":"open-pr","sim":0.4,"title":"…"}],
#             "split": ["…"] } }       # too-big only: suggested slices for /to-tickets
#
# Exit 0 ok · 64 usage · 79 required GitHub evidence unavailable (pause the run;
# a blind pre-flight never says proceed).
set -euo pipefail
# Fixed read commands: a malformed payload is GitHub's, so it halts (#32).
export SB_GITHUB_READ_STRICT=1

REPO=""; ISSUES=""; INFLIGHT=""; FILES=""; THRESHOLD="0.6"; CAP="400"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)      REPO="$2"; shift 2 ;;
    --issues|--issue) ISSUES="$2"; shift 2 ;;
    --inflight)  INFLIGHT="$2"; shift 2 ;;
    --files)     FILES="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --cap)       CAP="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$REPO" ] && [ -n "$ISSUES" ] || { echo "usage: --repo <owner/name> --issues <N[,M…]>" >&2; exit 64; }
echo "$ISSUES" | grep -Eq '^[0-9]+(,[0-9]+)*$' || { echo "--issues must be numbers: $ISSUES" >&2; exit 64; }
echo "$CAP" | grep -Eq '^[0-9]{1,10}$' || { echo "--cap must be a whole number of lines: $CAP" >&2; exit 64; }
CAP=$((10#$CAP))   # 0400 → 400: jq --argjson rejects leading zeros

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$HERE/super-board-gh-guard.sh" ]; then
  # shellcheck source=/dev/null
  . "$HERE/super-board-gh-guard.sh"
  sb_gh_guard_check 200 || exit $?
fi

MERGED=$(python3 "$HERE/super-board-github-read.py" --kind prs-merged -- pr list --repo "$REPO" --state merged --limit 100 --json number,title,body,url ) || exit $?
OPEN=$(python3 "$HERE/super-board-github-read.py" --kind prs-open -- pr list --repo "$REPO" --state open --limit 100 --json number,title,body,url,headRefName,files ) || exit $?
CLOSED=$(python3 "$HERE/super-board-github-read.py" --kind issues-closed -- issue list --repo "$REPO" --state closed --limit 100 --json number,title,body,stateReason ) || exit $?
CARDS="[]"
[ -n "$INFLIGHT" ] && CARDS=$(cat "$INFLIGHT")

TARGETS="[]"
for n in ${ISSUES//,/ }; do
  one=$(python3 "$HERE/super-board-github-read.py" --kind issue -- issue view "$n" --repo "$REPO" --json number,title,body ) || exit $?
  TARGETS=$(jq -c --argjson one "$one" '. + [$one]' <<<"$TARGETS")
done

jq -n --argjson targets "$TARGETS" --argjson merged "$MERGED" --argjson open "$OPEN" \
      --argjson closed "$CLOSED" --argjson cards "$CARDS" --arg files "$FILES" \
      --argjson hasinf "$([ -n "$INFLIGHT" ] && echo true || echo false)" \
      --argjson th "$THRESHOLD" --argjson cap "$CAP" '
  def stop: ["the","and","for","with","from","into","when","that","this","add","fix","make","use","should","not","are","can","new"];
  def toks: ascii_downcase | [scan("[a-z0-9]+")] | map(select(length > 2)) | . - stop | unique;
  def sim($a; $b): ($a | toks) as $x | ($b | toks) as $y
    | if ($x | length) == 0 or ($y | length) == 0 then 0
      else ((($x - ($x - $y)) | length) / (($x + $y) | unique | length) * 100 | floor) / 100 end;
  # GitHub closing keywords only: a PR that merely mentions #N is not delivering it.
  def closes($n): (.body // "") | test("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[ :]+#" + ($n | tostring) + "\\b");
  def closed_refs: [ (.body // "") | scan("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)[ :]+#([0-9]+)")[0] | tonumber ] | unique;
  def fps: [ (.body // "") | scan("(?m)^[ \t]*fingerprint:[ \t]*([^\n]*[^ \t\n])")[0] ];
  # Không tính dòng "Nguồn:"/"Source:" và tài liệu docs/plans/ (chỉ đọc, được trích làm nguồn) là file thẻ sẽ sửa.
  def paths: [ ((.body // "") | split("\n") | map(select(test("^[ \t]*[-*]?[ \t]*\\**(Nguồn|Source)\\**[ \t]*:"; "i") | not)) | join("\n"))
      | scan("[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+\\.[A-Za-z0-9]+") | select(test("^docs/plans/") | not) ] | unique;
  # Dòng tiêu đề mục "## <tên>": sau tên là hết từ (dấu cách, "(", ":", \r hoặc hết dòng). has_acs và sect dùng
  # chung để cùng nhận "## Acceptance Criteria (…)" và cùng bỏ "## Fixes", "## Fixture".
  def heading($h): test("^##[ \t]+" + $h + "(?!\\w)");
  # The AC section: lines after the LAST "## Acceptance Criteria" heading, up to the next "## ".
  def has_acs: ((.body // "") / "\n") as $l
    | [ $l | to_entries[] | select(.value | heading("Acceptance Criteria")) | .key ] as $h
    | if ($h | length) == 0 then false
      else [ $l[($h | last) + 1:][] ] as $t
        | ([ $t | to_entries[] | select(.value | test("^##[ \t]")) | .key ] | first) as $e
        | (if $e == null then $t else $t[:$e] end) | any(.[]; test("^[ \t]*(?:[-*]|[0-9]{1,2}[.)])[ \t]+\\S")) end;

  # Câu 5 — quá lớn? Regex trên chữ của issue (title + body), tất định. Chỉnh 19/10 trên 245 issue lấy bằng
  # `gh issue list --state all` ở 6 board: 6 thẻ builder đã chặn vì quá lớn (NFH #4 #13 #14 #54, OfficeReader
  # #98 #102) đều hold, 0/49 thẻ đóng COMPLETED có AC bị hold. Nghiêng về proceed: mọi tín hiệu tính 1 và cần
  # ≥2, trừ `device` tính 2 nên tự nó đủ hold — AC chỉ máy thật chứng minh được kéo theo cả bộ test trên thiết
  # bị (comment builder ở OfficeReader #98: riêng phần chứng minh ~800–1.100 dòng); agent hạ được khi nêu lý do.
  # Trần dòng là --cap (runner truyền merge_policy.auto_max_lines, mặc định 400); 0 = không trần: bỏ tín hiệu "nhiều việc".
  # Mục "## <tên>" cuối cùng của body (cùng luật tiêu đề với has_acs), tới "## " kế tiếp.
  def sect($h): ((.body // "") / "\n") as $l
    | [ $l | to_entries[] | select(.value | heading($h)) | .key ] as $k
    | if ($k | length) == 0 then ""
      else [ $l[($k | last) + 1:][] ] as $t
        | ([ $t | to_entries[] | select(.value | test("^##[ \t]")) | .key ] | first) as $e
        | (if $e == null then $t else $t[:$e] end) | join("\n") end;
  # Đầu việc của một danh sách: dấu tách trong `code` thành dấu cách (giữ nguyên chữ để gợi ý tách đọc được),
  # bỏ (chú thích), rồi tách ở xuống dòng, gạch đầu dòng, ";", ",", cuối câu và " + ".
  def parts: gsub("`(?<c>[^`\n]*)`"; "`" + (.c | gsub("[,;.+]"; " ")) + "`") | gsub("\\([^()\n]*\\)"; "")
    | gsub("(?m)^[ \t]*(?:[-*]|[0-9]+[.)]|[a-z][.)])[ \t]+"; "\n")
    | [ splits("[\n;,]|\\.(?:\\s|$)| \\+ ") | gsub("^\\s+|\\s+$"; "") | select(test("\\w")) ];
  # Vùng có thể ship và kiểm riêng (lint.md tiêu chí 15: UI, API, database, job…). Chữ viết tắt so đúng
  # hoa/thường ((?-i:…)) để "ui", "db", "api" trong câu thường không tính; bỏ từ quá chung (server, level, ad).
  def areas: {
    ui: "\\b(?:(?-i:UI|HUD)|paywall|giao diện|màn hình|prefab|scene)\\b",
    art: "\\b(?:art|model 3D|Blender|(?-i:FBX)|render|hoạt ảnh|animation|sprite|chibi)\\b",
    audio: "\\b(?:audio|âm thanh|sound|music)\\b",
    data: "\\b(?:save/load|Cloud Save|dữ liệu|database|(?-i:DB)|migration|schema)\\b",
    money: "\\b(?:(?-i:IAP)|Billing|thanh toán|payment|purchase)\\b",
    ads: "\\b(?:AdMob|LevelPlay|quảng cáo|ads)\\b",
    auth: "\\b(?:đăng nhập|login|sign-in|OAuth)\\b",
    analytics: "\\b(?:analytics|(?-i:GA4)|telemetry)\\b",
    l10n: "\\b(?:VI/EN|bản dịch|translation|localization|ngôn ngữ)\\b",
    remote: "\\b(?:Remote Config|(?-i:API)|backend|webhook)\\b",
    docs: "\\b(?:(?-i:GDD)|tài liệu|docs/)",
    a11y: "\\b(?:accessibility|trợ năng)\\b",
    settings: "\\b(?:settings|cài đặt)\\b",
    native: "\\b(?-i:JNI|NDK)\\b|C\\+\\+",
    content: "\\b(?:[0-9]+ tập|Tập [0-9]|màn [0-9])\\b" };
  def too_big:
    sect("Fix") as $fix | sect("Acceptance Criteria") as $ac
    | [ $fix | parts[] | select(test("^#?[0-9]+$|^[0-9a-f]{7,40}$") | not) ] as $items
    | [ $items[] | select([ scan("\\S+") ] | length <= 6) ] as $short
    | [ (.title // "") | sub("^\\S+ \\[\\w+\\] "; "") | gsub("\\([^()]*\\)"; "") | splits("(?<![0-9]),|,(?![0-9])|;")
        | gsub("^\\s+|\\s+$"; "") | select(length > 0) ] as $named
    | [ $ac / "\n" | .[] | select(test("^[ \t]*(?:[-*]|[0-9]{1,2}[.)])[ \t]+\\S"))
        | sub("^[ \t]*(?:[-*]|[0-9]{1,2}[.)])[ \t]+(?:\\[[ xX]\\][ \t]*)?"; "") ] as $acs
    | ([ (.title // ""), $fix, $ac ] | join("\n")) as $txt
    | [ areas | to_entries[] | select(.value as $re | $txt | test($re; "i")) | .key ] as $zones
    # Tự nhận lớn: tiêu đề là cả một giai đoạn / vertical slice ("Season", "epic" là tên tính năng game,
    # không tính); cụm "nhiều thành phần"… chỉ đọc ở Fix và Risk, nơi thẻ tự đánh giá phạm vi.
    | ( [ (.title // "") | scan("(?i)\\b(?:giai đoạn [0-9]+|phase [0-9]+|vertical slice)\\b") ]
      + [ $fix, sect("Risk") | scan("(?i)nhiều thành phần|phạm vi lớn|nhiều (?:module|hệ thống|mảng)|many (?:components|modules|areas)|large scope") ] ) as $self
    | [ $fix, $ac | scan("(?i)(?:hoàn thiện|hoàn chỉnh|đủ|toàn bộ|tất cả|complete|all)\\b[^\n]{0,60}\\btheo\\b[^\n]{0,40}§[ \t]*[0-9][0-9.]*") ] as $ref
    | [ $acs[] | select(test("(?i)\\b[0-9]+[ \t]*(?:người|people|users|testers)\\b|(?:không crash|crash-free)[^\n]*%|retention|giữ chân|số giờ thật|chạy thật|đăng nhập \\S+ thật")) ] as $people
    | [ $acs[] | select(test("(?i)\\bOOM\\b|\\bFPS\\b|bộ nhớ|\\bRAM\\b|nhiệt độ|thermal|(?:hao|tốn|sụt|mức) pin\\b|battery")) ] as $metric
    # Máy thật: AC luôn là tín hiệu (kể cả "Không OOM trên máy thật"). Ở Risk chỉ bỏ cụm phủ định sát ("không cần
    # máy thật", "no real device": từ phủ định + tối đa 2 từ không dấu câu + cụm); phần còn lại của dòng vẫn được đọc.
    | "máy thật|thiết bị thật|real device|physical device" as $dev
    | (($ac + "\n" + (sect("Risk") | gsub("(?i)\\b(?:không|no|not|without)(?:[ \t]+[^\\s,;.]+){0,2}[ \t]+(?:" + $dev + ")"; "")))
       | test("(?i)" + $dev)) as $realdev
    # work: tín hiệu "nhiều việc" (gợi ý tách theo việc); còn lại là AC phải tách ra thẻ `qa` riêng.
    # The Fix list and the title name the same work: when the Fix list is the signal but fits under a large cap,
    # the title is not read as a second chance (one signal for one list of work).
    | [ if ($short | length) >= 5 and ($short | length) * 5 >= ($items | length) * 4 then
          (if ($short | length) * 100 > $cap then
             { w: 1, work: true, split: $items,
               says: "Fix lists \($short | length) separate deliverables: at a rough ~100 changed lines each, ~\($short | length * 100) lines, over the \($cap)-line merge cap" }
           else empty end)
        elif ($named | length) >= 3 then
          { w: 1, work: true, split: $named, says: "the title names \($named | length) deliverables" }
        else empty end,
        if ($zones | length) >= 4 then
          { w: 1, work: true, split: [ $zones[] | "the \(.) part" ],
            says: "spans \($zones | length) areas (\($zones | join(", "))) that can each ship and be checked alone" }
        else empty end,
        if ($self | length) > 0 then
          { w: 1, work: true, split: [], says: "the card calls itself big: \"\($self[0])\"" } else empty end,
        if ($ref | length) > 0 then
          { w: 1, work: true, split: [ "one card per part of: \($ref[0])" ],
            says: "its scope is a whole spec section, not a list of changes: \"\($ref[0])\"" } else empty end,
        if ($people | length) > 0 then
          { w: 1, work: false, split: [ $people[] | "a qa card for: \(.)" ],
            says: "AC needs people or production data: \($people | join(" · "))" } else empty end,
        if ($metric | length) > 0 and $realdev then
          { w: 2, work: false, split: [ $metric[] | "a qa card for: \(.)" ],
            says: "AC only a real device can prove: \($metric | join(" · "))" } else empty end ] as $sig
    # --cap 0: no merge line cap, so "many deliverables" is no reason to split (one card = one PR = one gate).
    | (if $cap == 0 then [ $sig[] | select(.work | not) ] else $sig end) as $sig
    | { hold: (([ $sig[].w ] | add // 0) >= 2), evidence: [ $sig[].says ],
        split: (([ $sig[] | select(.work) | .split | select(length > 0) ] | first
                 // (if $cap == 0 then [] else [ "vertical slices, each under the \($cap)-line merge cap" ] end))
                + [ $sig[] | select(.work | not) | .split[] ]) };

  [ $targets[] | . as $i | $i.number as $n
    | ($i | fps) as $myfp
    | ($i | too_big) as $big
    | (if $files == "" then ($i | paths) else ($files / ",") end) as $mine
    # Own branch = this card coming back (rebuild, rebase); never its own duplicate.
    | [ $open[] | select((.headRefName // "") | startswith("issue-\($n)-") | not) ] as $others

    | ( [ $merged[] | select(closes($n)) | "PR #\(.number) merged and closes #\($n)" ]
      + [ $merged[] | select(($myfp | length) > 0 and (fps - (fps - $myfp) | length) > 0)
          | "PR #\(.number) merged with the same fingerprint" ]
      + [ $merged[] | select(sim(.title; $i.title) >= $th) | "PR #\(.number) merged: \"\(.title)\"" ]
      + [ $closed[] | select(.number != $n and .stateReason != "NOT_PLANNED")
          | select(sim(.title; $i.title) >= $th or (($myfp | length) > 0 and (fps - (fps - $myfp) | length) > 0))
          | "issue #\(.number) closed: \"\(.title)\"" ] ) as $done

    | ( [ $others[] | select(closes($n)) | "open PR #\(.number) (\(.headRefName)) already closes #\($n)" ]
      + [ $others[] | select(closes($n) | not) | select(sim(.title; $i.title) >= $th)
          | "open PR #\(.number) covers it: \"\(.title)\"" ]
      + [ $cards[] | select(.number != $n)
          | select(((.status as $s | ["Building","QA","Review"] | index($s)) != null)
                   or (.status == "Ready" and .number < $n))
          | select(sim(.title; $i.title) >= $th)
          | "card #\(.number) in \(.status) covers it: \"\(.title)\"" ] ) as $busy

    # #280: a card that already has its own open PR came back (rebuild/rebase): its overlap was accepted at the first
    # build, so it is not sequenced again (the merge gate rebases). With --inflight, only a PR that closes a card in
    # Ready/Building/QA/Review blocks: the PR of a Backlog/Blocked card may never close, so waiting on it is a deadlock.
    | ([ $open[] | select((.headRefName // "") | startswith("issue-\($n)-")) ] | length > 0) as $own
    | [ $cards[] | select((.status as $s | ["Ready","Building","QA","Review"] | index($s)) != null) | .number ] as $active
    | [ $others[] | select($own | not) | select(closes($n) | not) | select(sim(.title; $i.title) < $th)
        | . as $p | [ ($p.files // [])[] | .path ] as $pf
        # Shared append-only files every PR touches (own merge driver / regenerated): no overlap (#226 sat behind 8 PRs).
        | ($mine - [".agents/regression_matrix.active.json", "universal-agent-devkit/tests/lib/test_durations.txt",
                    ".agents/regression_status.json", ".agents/CHECKLIST.md", ".agents/instincts.md"]) as $own_files
        | ($own_files - ($own_files - $pf)) as $hit
        | select(($hit | length) > 0)
        | { pr: $p.number, files: $hit,
            issues: ($p | closed_refs | if $hasinf then map(select(. as $k | $active | index($k))) else . end) } ] as $overlap

    | ( [ $merged[] | { ref: "#\(.number)", kind: "merged-pr", title, sim: sim(.title; $i.title) } ]
        + [ $others[] | { ref: "#\(.number)", kind: "open-pr", title, sim: sim(.title; $i.title) } ]
        + [ $closed[] | select(.number != $n) | { ref: "#\(.number)", kind: "closed-issue", title, sim: sim(.title; $i.title) } ]
        + [ $cards[] | select(.number != $n) | { ref: "#\(.number)", kind: "card:\(.status)", title, sim: sim(.title; $i.title) } ]
        | map(select(.sim >= 0.25 and .sim < $th)) | sort_by(-.sim) | .[:5] ) as $near

    | { number: $n, title: $i.title, candidates: $near, blockedBy: [], conflictWith: [], _files: $mine, _own: $own }
      + ( if ($done | length) > 0 then
            { verdict: "hold", tag: "done", reason: "already delivered", evidence: $done }
          elif ($busy | length) > 0 then
            { verdict: "hold", tag: "in-progress", reason: "already being built elsewhere", evidence: $busy }
          elif ($i | has_acs | not) then
            { verdict: "hold", tag: "unclear", reason: "no `## Acceptance Criteria` items (`-`, `*`, `1.`, `1)`)", evidence: ["issue #\($n) body"] }
          elif $big.hold then
            { verdict: "hold", tag: "too-big", evidence: $big.evidence, split: $big.split,
              reason: (if $cap == 0 then "needs a step no agent can do — move it to a qa card, build the rest as one PR"
                       else "too big — split it with /to-tickets into cards under the \($cap)-line merge cap before building" end) }
          elif ($overlap | length) > 0 then
            { verdict: "sequence", tag: "overlap",
              reason: "open PRs touch the same files — build after them",
              evidence: [ $overlap[] | "open PR #\(.pr) touches \(.files | join(", "))" ],
              blockedBy: ([ $overlap[].issues[] ] | unique - [$n]),
              conflictWith: [ $overlap[].pr ] }
          else
            { verdict: "proceed", tag: "clean", reason: "no duplicate, no overlap", evidence: [] }
          end ) ]
  # Peer overlap: two cards checked together name the same files and neither has an open
  # PR yet. The lower-numbered one goes first; the other waits behind it. Sequencing both
  # against each other parks both forever (#180/#181 on 2026-10-03, corpus.ts).
  | sort_by(.number)
  | reduce .[] as $c ({out: [], go: []};
      ([ .go[] | select((.files - (.files - $c._files)) | length > 0) ] | first) as $first
      | if $c.verdict == "proceed" and $first != null and ($c._own | not) then
          .out += [ $c + { verdict: "sequence", tag: "overlap",
                           reason: "a lower-numbered card in this check touches the same files — build after it",
                           evidence: [ "#\($first.number) touches \(($first.files - ($first.files - $c._files)) | join(", "))" ],
                           blockedBy: [ $first.number ] } ]
        elif $c.verdict == "proceed" then
          .out += [ $c ] | .go += [ { number: $c.number, files: $c._files } ]
        else .out += [ $c ] end)
  | .out | map(del(._files, ._own))
  | INDEX(.number | tostring)'
