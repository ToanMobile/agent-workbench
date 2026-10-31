#!/usr/bin/env bash
# bin/ocr-review (2026-10-13, user: "đưa ocr vào qui trình … giải thích sao ocr hổm nay không work"): `ocr review` (OpenCodeReview
# v1.12.13) sends the diff to an LLM and refuses to start without an endpoint ("no valid LLM endpoint configured"); this machine has
# none (no OCR_LLM_*, no ~/.opencodereview/config.json, no ANTHROPIC_* — Claude Code's own login is not an API key), so every
# `ocr review` exited 1 at once and the agents went on with a subagent review: 2 real ocr calls in 14 days over 5 repos.
# bin/ocr-review runs the mode the machine can: the full LLM review when an endpoint answers, otherwise OCR's delegation mode
# (`ocr delegate preview` + `ocr delegate rule`, no LLM, no key) written as a review spec for a fresh-context reviewer.
# Everything goes to a temp folder, never into the repo. A fake `ocr` on PATH keeps the test offline and deterministic.
# OpenCodeReview of the helper (13/10): `-b TEXT` reached `ocr delegate` as a stray argument; a file name went into the spec's shell
# command unquoted; `--out` followed a symlink or a folder of another user; keys outside the `sk-xx-` / bearer forms were printed.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DEVKIT_DIR/bin/ocr-review"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def f(x):\n    return x\n' > a.py && git add -A && git commit -qm init
printf 'def f(x):\n    return 1 / x\n' > a.py

# fake ocr: OCR_FAKE=noendpoint|endpoint|empty
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "review "*)
    if [ "$OCR_FAKE" = badkey2 ]; then
      echo "Error: 401 key sk-""abcdefghijklmnopqrstuvwxyzABCDEF0123456789 api_""key=ZZq9ZZq9ZZq9ZZq9ZZ aws AKIA""FAKEFAKE12345678" >&2; exit 1   # split: no key-shaped literal in this file
    fi
    if [ "$OCR_FAKE" = badkey ]; then
      echo "Error: anthropic: 401 invalid x-api-key sk-""ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 for model claude-sonnet-5-5" >&2; exit 1
    fi
    case "$OCR_FAKE" in quota|partial|tokens|done1|reused|nonprov|status|nofail)   # ocr v1.13 writes its report, then exits 1 (measured 14/10)
      out=""; prev=""
      for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
      F2='[{"path":"a.py","classification":"provider"},{"path":"b.py","classification":"provider"}]'   # the quota fixture's failures
      case "$OCR_FAKE" in   # each differs from quota in ONE field, so each guard of rejected_all is tested on its own
        tokens) printf '{"status":"failed","summary":{"total_tokens":812},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[],"reused":[],"failed":%s}}}\n' "$F2" > "$out"; exit 1 ;;
        done1) printf '{"status":"failed","summary":{"total_tokens":0},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[{"path":"a.py"}],"reused":[],"failed":[{"path":"b.py","classification":"provider"}]}}}\n' > "$out"; exit 1 ;;
        reused) printf '{"status":"failed","summary":{"total_tokens":0},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[],"reused":[{"path":"c.py"}],"failed":%s}}}\n' "$F2" > "$out"; exit 1 ;;
        status) printf '{"status":"complete","summary":{"total_tokens":0},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[],"reused":[],"failed":%s}}}\n' "$F2" > "$out"; exit 1 ;;
        nofail) printf '{"status":"failed","summary":{"total_tokens":0},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[],"reused":[],"failed":[]}}}\n' > "$out"; exit 1 ;;
        nonprov) printf '{"status":"failed","summary":{"total_tokens":0},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[],"reused":[],"failed":[{"path":"a.py","classification":"provider"},{"path":"b.py","classification":"parse"}]}}}\n' > "$out"; exit 1 ;;
      esac
      if [ "$OCR_FAKE" = quota ]; then
        printf '{"status":"failed","summary":{"files_reviewed":2,"total_tokens":0},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[],"reused":[],"failed":[{"path":"a.py","classification":"provider"},{"path":"b.py","classification":"provider"}]}}}\n' > "$out"
        echo 'LLM completion error: POST "https://api.anthropic.com/v1/messages": 400 Bad Request {"type":"invalid_request_error","message":"You have reached your specified API usage limits. You will regain access on 2026-11-01 at 00:00 UTC."}' >&2
      else
        printf '{"status":"failed","summary":{"files_reviewed":2,"total_tokens":5321},"manifest":{"coverage":{"selected":[{"path":"a.py"},{"path":"b.py"}],"completed":[{"path":"a.py"}],"reused":[],"failed":[{"path":"b.py","classification":"provider"}]}}}\n' > "$out"
        echo "Error: review failed: 1 of 2 selected item(s) failed" >&2
      fi
      exit 1 ;;
    esac
    if [ "$OCR_FAKE" = endpoint ]; then
      [ -n "${OCR_ARGS_LOG:-}" ] && echo "$*" >> "$OCR_ARGS_LOG"
      case " $* " in *" --from "*) case " $* " in *" --to "*) ;; *) echo "Error: --to is required when --from is specified" >&2; exit 1 ;; esac ;; esac
      out=""; prev=""
      for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
      printf '{"comments":[{"path":"a.py","line":2,"message":"division by zero when x == 0"}]}\n' > "$out"; exit 0
    fi
    echo "Error: resolve LLM endpoint: no valid LLM endpoint configured; one of OCR_LLM_URL/OCR_LLM_TOKEN/OCR_LLM_MODEL, ~/.opencodereview/config.json, or ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN/ANTHROPIC_MODEL must be set" >&2; exit 1 ;;
  "delegate preview")
    [ -n "${OCR_ARGS_LOG:-}" ] && echo "$*" >> "$OCR_ARGS_LOG"
    if [ "$OCR_FAKE" = space ]; then
      printf '{"schema_version":"1","reviewable_count":1,"reviewable_files":[{"path":"my file;x.py","status":"added","insertions":1,"deletions":0}]}\n'; exit 0
    fi
    if [ "$OCR_FAKE" = empty ]; then
      printf '{"schema_version":"1","mode":"workspace","reviewable_count":0,"reviewable_files":[],"excluded_files":[]}\n'; exit 0
    fi
    printf '{"schema_version":"1","mode":"workspace","reviewable_count":1,"reviewable_files":[{"path":"a.py","status":"modified","insertions":1,"deletions":1}],"excluded_files":[]}\n'; exit 0 ;;
  "delegate rule")
    printf '{"schema_version":"1","groups":[{"group_id":1,"files":["a.py"],"rule":"#### Boundary and Edge-Case Handling\\n- ZeroDivisionError when a divisor can be zero"}]}\n'; exit 0 ;;
esac
echo "fake ocr: unexpected $*" >&2; exit 9
SH
chmod +x "$TMP/bin/ocr"
run() { PATH="$TMP/bin:$PATH" OCR_FAKE="$1" python3 "$HELPER" > "$TMP/out" 2> "$TMP/err"; echo $?; }

# 1. no endpoint: delegation spec, exit 0, nothing written into the repo
rc="$(run noendpoint)"
spec="$(sed -n 's/^spec: //p' "$TMP/out")"
[ "$rc" = 0 ] && grep -q '^mode: delegate' "$TMP/out" && ok "no LLM endpoint: falls back to delegation (exit 0)" \
  || fail "no endpoint: rc=$rc out=$(head -3 "$TMP/out" | tr '\n' ' ') err=$(head -2 "$TMP/err" | tr '\n' ' ')"
[ -n "$spec" ] && [ -f "$spec" ] && grep -q 'a.py' "$spec" && grep -q 'ZeroDivisionError' "$spec" && grep -q 'git diff' "$spec" \
  && ok "the spec names the file, its diff command and OCR's rule" || fail "spec missing or incomplete: '$spec'"
grep -q 'no valid LLM endpoint' "$TMP/out" "$TMP/err" && ok "it says WHY it fell back (the endpoint error)" || fail "fallback reason not shown"
case "$spec" in "$R"/*) fail "spec written inside the repo: $spec" ;; *) ok "spec is outside the repo" ;; esac
[ -z "$(git status --porcelain -- . ':!a.py')" ] && ok "repo untouched (no stray file)" || fail "stray files: $(git status --porcelain)"

# 2. endpoint configured: the full OCR review, its JSON report
rc="$(run endpoint)"
report="$(sed -n 's/^report: //p' "$TMP/out")"
[ "$rc" = 0 ] && grep -q '^mode: review' "$TMP/out" && [ -f "$report" ] && grep -q 'division by zero' "$report" \
  && ok "endpoint configured: runs ocr review, keeps its JSON report" || fail "endpoint: rc=$rc out=$(head -3 "$TMP/out" | tr '\n' ' ')"

# 3. nothing reviewable: says so, exit 0
rc="$(run empty)"
[ "$rc" = 0 ] && grep -qi 'nothing to review' "$TMP/out" && ok "no reviewable file: says so (exit 0)" || fail "empty: rc=$rc out=$(cat "$TMP/out")"

# 2b. the endpoint rejects EVERY request (14/10: the API key hit its usage limit until 01/11, every file "provider" failed, 0 tokens):
#     no review can run, so it is no endpoint — delegation, exit 0, the reason shown; a review that half ran stays a failure (exit 1)
rc="$(run quota)"
[ "$rc" = 0 ] && grep -q '^mode: delegate' "$TMP/out" && grep -q '^spec: ' "$TMP/out" && grep -q 'LLM endpoint unusable' "$TMP/out" \
  && grep -q 'usage limits' "$TMP/out" && ok "every request rejected (usage limit): falls back to delegation, says why (exit 0)" \
  || fail "quota: rc=$rc out=$(head -3 "$TMP/out" | tr '\n' ' ') err=$(head -2 "$TMP/err" | tr '\n' ' ')"
rc="$(run partial)"
[ "$rc" = 1 ] && ! grep -q '^mode: delegate' "$TMP/out" && ok "  … a review that reviewed some files and failed others: exit 1, no fallback" \
  || fail "partial failure fell back (rc $rc): $(head -3 "$TMP/out" | tr '\n' ' ')"
for m in tokens done1 reused nonprov status nofail; do   # the LLM answered (tokens), a file completed or was reused, or a failure is not the provider's
  # the fixture itself must be OCR's shape (a typo would make rejected_all return False for the wrong reason and the case pass anyway)
  PATH="$TMP/bin:$PATH" OCR_FAKE="$m" ocr review -o "$TMP/fx.$m.json" 2>/dev/null
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); c=d["manifest"]["coverage"]; [c[k] for k in ("selected","completed","reused","failed")]; d["summary"]["total_tokens"]; d["status"]; assert d["status"] in ("failed","complete") and all(f["classification"] in ("provider","parse") for f in c["failed"])' "$TMP/fx.$m.json" 2>/dev/null \
    || fail "  … fixture $m is not OCR's report shape"
  rc="$(run "$m")"
  [ "$rc" = 1 ] && ! grep -q '^mode: delegate' "$TMP/out" && grep -q '`ocr review` failed' "$TMP/err" && ok "  … $m: not 'every request rejected', exit 1, no fallback" \
    || fail "$m fell back to delegation (rc $rc): $(head -2 "$TMP/out" | tr '\n' ' ')"
done

rc="$(PATH="$TMP/bin:$PATH" OCR_FAKE=quota python3 "$HELPER" --out "$TMP/reuse" > /dev/null 2>&1; PATH="$TMP/bin:$PATH" OCR_FAKE=badkey python3 "$HELPER" --out "$TMP/reuse" > "$TMP/out" 2> "$TMP/err"; echo $?)"
[ "$rc" = 1 ] && ! grep -q '^mode: delegate' "$TMP/out" && ok "  … a reused --out: the last run's 'every request rejected' report never stands in for a run that wrote none" \
  || fail "stale report from the previous run read as this run's (rc $rc): $(head -2 "$TMP/out" | tr '\n' ' ')"

# 3b. an auth error that echoes a key: the helper fails (exit 1) and never prints the key
rc="$(run badkey)"
[ "$rc" = 1 ] && ok "a failing ocr review (auth error): exit 1" || fail "auth error: rc=$rc"
! grep -q 'AbCdEfGhIjKlMnOp' "$TMP/out" "$TMP/err" && grep -q '\*\*\*' "$TMP/err" && ok "the key in the error is masked" \
  || fail "key printed: $(cat "$TMP/err" | head -2)"

# 3c. other key forms in an error are masked too
rc="$(run badkey2)"
! grep -q -e 'abcdefghijklmnop' -e 'ZZq9ZZq9ZZq9' -e 'FAKEFAKE1234' "$TMP/out" "$TMP/err" && ok "sk-<long>, api_key= and AKIA keys masked" \
  || fail "a key form printed: $(head -2 "$TMP/err")"

# 3d. -b TEXT is a review-only flag: its value never reaches ocr delegate
: > "$TMP/args"
PATH="$TMP/bin:$PATH" OCR_FAKE=noendpoint OCR_ARGS_LOG="$TMP/args" python3 "$HELPER" -b "focus on auth" > "$TMP/out" 2> "$TMP/err"
! grep -q 'focus on auth' "$TMP/args" && grep -q 'preview' "$TMP/args" && ok "-b value kept out of ocr delegate preview" \
  || fail "delegate preview got: $(cat "$TMP/args")"

# 3e. a file name with shell characters is quoted in the spec's command
PATH="$TMP/bin:$PATH" OCR_FAKE=space python3 "$HELPER" --delegate-only > "$TMP/out" 2> "$TMP/err"
spec="$(sed -n 's/^spec: //p' "$TMP/out")"
grep -qF "'my file;x.py'" "$spec" 2>/dev/null && ok "the spec quotes a file name with a space and ;" || fail "unquoted: $(grep 'my file' "$spec" 2>/dev/null)"

# 3f. --out must be this user's own real folder, not a symlink
mkdir -p "$TMP/elsewhere"; ln -s "$TMP/elsewhere" "$TMP/link"
rc="$(PATH="$TMP/bin:$PATH" OCR_FAKE=noendpoint python3 "$HELPER" --delegate-only --out "$TMP/link" > "$TMP/out" 2> "$TMP/err"; echo $?)"
[ "$rc" = 1 ] && [ -z "$(ls -A "$TMP/elsewhere")" ] && ok "--out that is a symlink: refused (exit 1), nothing written through it" \
  || fail "--out symlink: rc=$rc, wrote: $(ls "$TMP/elsewhere")"

# 3g. --from alone (what review_gate tells an agent to run for committed code): the helper adds --to HEAD, as its spec already reads
base="$(git -C "$R" rev-parse HEAD)"
rc="$(PATH="$TMP/bin:$PATH" OCR_FAKE=endpoint OCR_ARGS_LOG="$TMP/rng.args" python3 "$HELPER" --from "$base" --out "$TMP/rng" > "$TMP/out" 2> "$TMP/err"; echo $?)"
[ "$rc" = 0 ] && grep -q '^mode: review' "$TMP/out" && grep -q -- "--from $base --to HEAD" "$TMP/rng.args" \
  && ok "--from without --to: the review runs to HEAD (exit 0, ocr got --to HEAD)" || fail "--from alone: rc=$rc $(cat "$TMP/err" "$TMP/rng.args" 2>&1)"

# 4. ocr not installed: exit 3 with the install hint
rc="$(PATH="/usr/bin:/bin" python3 "$HELPER" > "$TMP/out" 2> "$TMP/err"; echo $?)"
[ "$rc" = 3 ] && grep -qi 'npm' "$TMP/out" "$TMP/err" && ok "ocr missing: exit 3 with the install hint" || fail "missing: rc=$rc"

# BUG-REV-ocr-review-tmp-leak: a run without --out that ends in an error leaves no ocr-review.* folder in $TMPDIR
TD="$TMP/tmpdir"; mkdir -p "$TD"
TMPDIR="$TD" PATH="$TMP/bin:$PATH" OCR_FAKE=badkey python3 "$HELPER" --strict > /dev/null 2>&1
[ -z "$(ls -A "$TD")" ] && ok "failed run without --out: its temp folder is removed" || fail "temp folder leaked: $(ls "$TD")"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
