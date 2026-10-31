#!/usr/bin/env bash
# bin/review-full.py (review-fanout.sh --full): the 4-way review of the WHOLE solution with stub reviewers (no LLM, no
# network): separate clones / node_modules / docs / lockfiles are excluded, files are chunked by module (tests last), all 4
# reviewers run (OCR once over a scratch copy), findings are cite-checked, deduped with a consensus count, known bug patterns
# on ANY line are P0, a reviewer that cannot run (Grok out of credit) is reported, and nothing is fixed or recorded.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
STUB="$TMP/stub"; mkdir -p "$STUB"
F1='{"severity":"P1","category":"bug","file":"src/app.py","line":2,"snippet":"return items[0]","problem":"IndexError when items is empty"}'
cat > "$STUB/claude" <<SH
#!/usr/bin/env bash
p="\$(cat)"
case "\$p" in
  *VERIFIER*) r='{"verifications":[]}' ;;
  *src/app.py*) r='{"verdict":"fail","findings":[$F1]}' ;;
  *) r='{"verdict":"pass","findings":[]}' ;;
esac
python3 -c 'import json,sys; print(json.dumps({"type":"result","is_error":False,"result":sys.argv[1],"total_cost_usd":0.01,"usage":{"input_tokens":5,"output_tokens":5},"modelUsage":{"claude-opus-4-5":{"outputTokens":5}}}))' "\$r"
SH
cat > "$STUB/grok" <<SH
#!/usr/bin/env bash
[ -f "$STUB/grok.nocredit" ] && { echo '{"type":"error","message":"API error (status 402 Payment Required): Grok Build usage balance exhausted"}'; exit 1; }
pf=""; while [ \$# -gt 0 ]; do [ "\$1" = --prompt-file ] && pf="\$2"; shift; done
if grep -q 'src/app.py' "\$pf"; then r='{"verdict":"fail","findings":[$F1]}'; else r='{"verdict":"pass","findings":[]}'; fi
python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"usage":{"total_tokens":9},"modelUsage":{"grok-4.7":{"outputTokens":9}}}, indent=2))' "\$r"
SH
cat > "$STUB/ocr" <<'SH'
#!/usr/bin/env bash
[ "$1" = review ] || exit 0
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
ls -R . > "$STUB_DIR/ocr.seen"
printf '{"status":"completed","comments":[],"manifest":{"coverage":{"completed":["src/app.py"],"failed":[]}},"summary":{"total_tokens":3}}' > "$out"
SH
echo "const fs=require('fs');const a=process.argv;fs.appendFileSync(process.env.STUB_DIR+'/agy.scopes',a[a.indexOf('--scope')+1]+'\n');fs.appendFileSync(process.env.STUB_DIR+'/agy.labels',a[a.indexOf('--label')+1]+'\n');fs.writeFileSync(a[a.indexOf('--out')+1],JSON.stringify({reviewer:'antigravity',status:'ok',verdict:'pass',findings:[]}));" > "$STUB/agy.js"
chmod +x "$STUB/claude" "$STUB/grok" "$STUB/ocr"
unset REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL
export STUB_DIR="$STUB" PATH="$STUB:$PATH" REVIEW_CLAUDE_BIN="$STUB/claude" REVIEW_GROK_BIN="$STUB/grok" REVIEW_AGY_CLI="$STUB/agy.js"

P="$TMP/p"; mkdir -p "$P/.agents" "$P/src" "$P/lib" "$P/tests" "$P/mcp-servers/rea" "$P/mcp-servers/super-board" "$P/node_modules/x" "$P/docs"
printf '### [INSTINCT-001] Silent except\n- **Quy tắc phòng ngừa & Cách fix:** log it\n- **detect:** `except:\\s*pass`\n- **detect-glob:** `*.py`\n' > "$P/.agents/instincts.md"
printf 'def g(items):\n    return items[0]\n' > "$P/src/app.py"
printf 'def h():\n    try:\n        return 1\n    except: pass\n' > "$P/lib/old.py"
printf 'from src.app import g\n\ndef test_g():\n    assert g([1]) == 1\n' > "$P/tests/test_app.py"
echo 'except: pass' > "$P/mcp-servers/rea/clone.py"; echo 'x' > "$P/mcp-servers/super-board/clone.sh"
echo 'module.exports=1' > "$P/node_modules/x/i.js"; echo '# doc' > "$P/docs/a.md"; echo '{}' > "$P/package-lock.json"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git add -A -f && git commit -qm i)
F="$DEVKIT_DIR/bin/review-fanout.sh"

bash "$F" --full --repo "$P" --list --chunk-lines 500 > "$TMP/list" 2>&1
grep -q 'files in scope' "$TMP/list" && ! grep -q -E 'rea|super-board|node_modules|docs' "$TMP/list" \
  && ok "--list: chunks without the clones, node_modules, docs" || { fail "--list"; cat "$TMP/list"; }

bash "$F" --full --repo "$P" --list --paths "lib/,tests/test_app.py,mcp-servers/rea/" > "$TMP/list2" 2>&1
grep -q '^2 files in scope' "$TMP/list2" && grep -q 'lib' "$TMP/list2" && ! grep -q -E 'rea|src' "$TMP/list2" \
  && ok "--paths limits the scan to the named files/folders (excludes still apply)" || { fail "--paths"; cat "$TMP/list2"; }
bash "$F" --full --repo "$P" --list --paths "nope/" > /dev/null 2>&1; [ $? = 2 ] \
  && ok "--paths matching nothing → exit 2" || fail "--paths empty"

bash "$F" --full --repo "$P" --out "$TMP/run" --chunk-lines 6 > "$TMP/out" 2>&1; rc=$?
S="$TMP/run/full-summary.json"
[ "$rc" = 1 ] && [ -s "$S" ] && ok "full scan with a P1 + a recurring bug → exit 1, summary written" || { fail "rc=$rc"; cat "$TMP/out"; }
q() { python3 -c "import json,sys; s=json.load(open('$S')); print($1)"; }
[ "$(q 'sorted(s["reviewers"])')" = "['antigravity', 'claude', 'grok', 'ocr', 'registry', 'verifier']" ] \
  && ok "all 4 reviewers (+ registry, verifier) ran" || fail "reviewers: $(q 's["reviewers"]')"
[ "$(q 'all(v["status"]=="ok" for v in s["reviewers"].values())')" = True ] && ok "every reviewer ok on every chunk" || fail "$(q 's["reviewers"]')"
[ "$(q 'sorted({p for c in json.load(open("'"$TMP/run/plan.json"'"))["chunks"] for p in c["files"]})')" = \
  "['.agents/instincts.md', 'lib/old.py', 'src/app.py', 'tests/test_app.py']" ] 2>/dev/null \
  || [ "$(q 'sorted({p for c in json.load(open("'"$TMP/run/plan.json"'"))["chunks"] for p in c["files"]})')" = "['lib/old.py', 'src/app.py', 'tests/test_app.py']" ] \
  && ok "scope = tracked source files minus exclusions" || fail "scope: $(q 'json.load(open("'"$TMP/run/plan.json"'"))["chunks"]')"
[ "$(q 'len(s["chunks"]) >= 2')" = True ] && ok "chunked by module ($(q 'len(s["chunks"])') chunks)" || fail "not chunked"
[ "$(q '[(c["severity"], c["state"], c["reviewers"], c["file"], c["line"]) for c in s["findings"] if c["file"]=="src/app.py"]')" = \
  "[('P1', 'blocking', ['claude', 'grok'], 'src/app.py', 2)]" ] && ok "P1 deduped across Claude + Grok (consensus 2), file:line kept" \
  || fail "app finding: $(q '[(c["severity"], c.get("state"), c["reviewers"]) for c in s["findings"]]')"
[ "$(q '[(c["severity"], c["known_pattern"], c["file"], c["line"]) for c in s["findings"] if c["file"]=="lib/old.py"]')" = \
  "[('P0', 'INSTINCT-001', 'lib/old.py', 4)]" ] && ok "known bug pattern on an existing (not added) line → P0" || fail "registry: $(q 's["findings"]')"
grep -q 'app.py' "$STUB/ocr.seen" && ! grep -q -E 'clone|node_modules' "$STUB/ocr.seen" && ok "OCR reviewed a scratch copy of the selection" || fail "ocr scope"
grep -qx full "$STUB/agy.scopes" && ok "Antigravity audits with --scope full" || fail "agy scope: $(cat "$STUB/agy.scopes")"
[ "$(sort "$STUB/agy.labels" | uniq -d | wc -l | tr -d ' ')" = 0 ] && [ "$(wc -l < "$STUB/agy.labels" | tr -d ' ')" -ge 2 ] \
  && ok "each chunk's Antigravity audit has its own label (no task-id clash)" || fail "agy labels: $(cat "$STUB/agy.labels")"
(cd "$P" && git status --porcelain | grep -q .) && fail "the scan changed the repo" || ok "report only: the repo is untouched"
[ -z "$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
print(" ".join(k for k in rc.load_view(sys.argv[2])["items"] if k.startswith("BUG-REV-")))' "$DEVKIT_DIR/bin" "$P" 2>/dev/null)" ] \
  && ok "no bug row recorded (report only)" || fail "full scan recorded bug rows"

touch "$STUB/grok.nocredit"
bash "$F" --full --repo "$P" --out "$TMP/run2" > "$TMP/out2" 2>&1; rc=$?
S="$TMP/run2/full-summary.json"
[ "$rc" = 1 ] && [ "$(q 's["reviewers"]["grok"]["status"]')" = failed ] && grep -q '402' "$S" \
  && ok "Grok out of credit → reported as failed (402), scan FAIL" || { fail "grok nocredit rc=$rc"; cat "$TMP/out2"; }

if [ "$FAILS" -ne 0 ]; then echo "review full: $FAILS FAILED"; exit 1; fi
echo "review full: all checks passed"
