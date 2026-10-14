#!/usr/bin/env bash
# hooks/test_evidence_gate.sh, check 7 (the OUTCOME reader): a reply that only TALKS about the outcome phrase is no outcome claim.
# Replay of the Stop blocks of 7 days of real transcripts (scripts/governance/stop_replay.py, 2026-10-14): of 48 CHECK 7 blocks,
# 8 replies held the phrase only inside quotes, and 2 blocks were plainly about the gate, not about a fix:
#   - `…có chữ "đã xử lý"…`                          the word is the subject (quoted_mention knew it for test claims only)
#   - `…chưa phải "đã fix" theo chuẩn của hook`       a negation: NEG_BEFORE_RESULT did not know "chưa phải"
# Each such reply was blocked again for explaining the block, so one false block cost a chain of them. Two-way: those pass; a
# quoted RESULT with no naming word (Kết quả: "đã fix"), an unquoted claim next to a mention, a negation that a break separates
# from the claim, a naming word that is also an ordinary one (từ = "from", claim = the agent's own assertion, regex / mẫu / pattern
# as nouns of the sentence: OCR + principal-code-reviewer 14/10), an odd quote and a rhetorical "(chẳng|không) phải … sao?" are
# still blocks (the gate's own rule: typography must not become a bypass). The 6 other quoted replies (`mình viết "…"`,
# `bằng chứng cho "đã fix"`, `Trả lời "…"`) stay blocked: nothing in them says "mention" that a bypass could not copy.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${TE_HOOK:-$DEVKIT_DIR/hooks/test_evidence_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P"; git -C "$P" init -q .
TR="$TMP/t.jsonl"; : > "$TR"
N=0
# check <want rc> <reply> [marker]: the hook on an empty transcript and a project with no test XML, so a claim it reads is unbacked
# (rc 2). A block must be the one this file is about: its message holds "CHECK 7" (an outcome claim), or `marker` ("TEST-EVIDENCE" for a
# test-pass claim), so another check of the hook can not make a case look green.
check() {
  local want="$1" text="$2" marker="${3:-CHECK 7}" rc
  N=$((N + 1))
  python3 -c 'import json,sys; print(json.dumps({"session_id":"te-out-"+sys.argv[3],"transcript_path":sys.argv[1],"last_assistant_message":sys.argv[2]}))' \
    "$TR" "$text" "$N" > "$TMP/in.json"
  CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err"
  rc=$?
  grep -q Traceback "$TMP/err" && rc=99
  if [ "$rc" = 2 ] && ! grep -q "$marker" "$TMP/err"; then fail "rc 2 but not by '$marker': $text"; return; fi
  if [ "$rc" = "$want" ]; then ok "rc $rc: $text"; else fail "rc $rc (want $want): $text"; fi
}

# the phrase is the subject of its clause: a naming word right before the quote, or a "chưa phải" right before the phrase
check 0 'Hook chặn vì câu của tôi có chữ "đã xử lý" trong phần giải thích, không vì tôi sửa gì.'
check 0 'Ngay câu này có chữ "đã xử lý" và chữ "đã fix", nên hook chặn.'
check 0 'Cụm từ "đã fix" là thứ hook đọc, không phải kết quả.'
check 0 'The word "fixed" is what the hook reads.'
check 0 'Bản vá có test bắt được khi gỡ, chưa phải "đã fix" theo chuẩn của hook.'
check 0 'Bản vá này chưa phải đã fix theo chuẩn của hook, vì thiếu cặp ĐỎ→XANH.'
check 0 'Bản vá này chưa phải là đã fix theo chuẩn của hook.'
check 0 'Bản vá có test bắt được khi gỡ, chưa phải là "đã fix" theo chuẩn của hook.'
# the gate's own rule stays: no bare-quote bypass, a real claim next to a mention, a negation cut off by a break, a naming word that
# is also an ordinary word (từ = "from"; claim = what an agent calls its own assertion), a rhetorical question
check 2 'Kết quả: "đã fix".'
check 2 'Cụm "đã fix" là chữ của hook, và tôi đã fix lỗi tràn bộ nhớ.'
check 2 'Mình đã fix lỗi tràn bộ nhớ.'
check 2 'Chưa phải tất cả, nhưng đã fix lỗi X.'
check 2 'Status: `fixed`.'
check 2 'Claim: "đã fix".'
check 2 'Claim: "12/12 test pass".' 'TEST-EVIDENCE'
check 2 'Từ bản v2: "đã fix lỗi X".'
check 2 'Chẳng phải đã fix lỗi X rồi sao?'
check 2 'Chẳng phải 12/12 test pass rồi sao?' 'TEST-EVIDENCE'
check 2 'Không phải đã fix lỗi X rồi sao?'
check 2 'Không phải đã fix lỗi X rồi à?'
check 2 'Tôi không phải đã fix lỗi X một mình, mà cùng reviewer.'
check 2 'Không phải 12/12 test pass rồi sao?' 'TEST-EVIDENCE'
# the naming word must stand right before the opening quote, and the match start right after it (principal-code-reviewer + OCR 14/10):
# a word of an earlier clause, a word of the same clause that only names a noun, a phrase over two quotes, an odd quote: a claim
check 2 'Tôi sửa regex trong hook, lỗi tràn bộ nhớ: "đã fix".'
check 2 'Đã cập nhật mẫu báo cáo, còn lỗi crash thì "đã khắc phục".'
check 2 'Pattern updated, the crash: `fixed`.'
check 2 'Chữ "lỗi" trong ticket nay "đã được sửa".'
check 2 'Cụm `đã fix` khớp, và mẫu "bug" ở log giờ "đã được sửa".'
check 2 'Theo mẫu báo cáo lỗi crash "đã khắc phục".'
check 2 'Per the terms the crash is "fixed".'
check 2 'Lỗi pattern matching "đã fix".'
check 2 'The regex bug is `fixed`.'
check 2 'Lỗi mẫu báo cáo "đã xử lý".'
check 2 'Mẫu regex là "[^"]*" và tôi đã fix lỗi X ở "parser".'
check 2 'Màn 5" và "regex" đã fix lỗi X "ok".'
check 2 'Bỏ ký tự " thừa trong "regex" đã fix lỗi parse "abc".'
check 2 'Cụm "x, đã fix lỗi Y".'
check 2 'Màn 5" và 7" chữ" đã fix" thôi.'
check 2 'Chữ "x đã fix".'
# the quote holds the NAMED PHRASE and nothing else: a quote that goes on with the object of the fix is a claim
check 2 'Chữ "lỗi tràn bộ nhớ đã được sửa".'
check 2 'Chữ "bug crash ở checkout không còn tái hiện".'
check 2 'Chữ "đã fix lỗi X".'
check 2 'Chữ "đã khắc phục crash ở checkout".'
check 2 'Chữ "đã fix lỗi tràn bộ nhớ và đã deploy prod".'
# only a word that names a quote and nothing else counts: regex / pattern / mẫu are nouns of the sentence ("Lỗi regex "đã fix""), and
# "words" is also the connective of "in other words"
check 2 'Lỗi regex "đã fix".'
check 2 'Bug pattern `fixed`.'
check 2 'Lỗi mẫu "đã khắc phục".'
check 2 'In other words "fixed".'
check 2 'In other  words "fixed".'
# controls that already behaved (must not move)
check 0 'Chưa fix được lỗi này, đang tìm nguyên nhân.'
check 0 'Cần đã fix xong mới báo, nên tôi chưa báo gì.'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
