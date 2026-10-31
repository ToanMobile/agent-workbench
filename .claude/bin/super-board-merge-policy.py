#!/usr/bin/env python3
"""super-board-merge-policy.py — decide which machine gates a PR must pass and which migrations run.

Called by super-board-merge-gate.sh inside the merge lock. Pure function of the
config, the PR metadata and the diff; no network, no side effects.

    super-board-merge-policy.py --config <cfg.json> --meta <pr.json> --diff <file>

`--meta` is `gh pr view --json labels,files,additions,deletions,body`.
`--diff` is `gh pr diff` (only ADDED lines are searched for keywords).

Stdout, one JSON object:
    { "human":      [ {"category": "size", "why": "big PR — please review: …"} ],
      "machine_gate": [ {"category": "money", "why": "path src/billing/charge.ts"} ],
      "require":    { "deep_review": true, "security_reviewer": true,
                      "verify_commands": [ "npm run test:payments" ] },
      "migrations": [ "supabase/migrations/2026_add_col.sql" ],
      "run":        [ {"env": "staging", "cmd": "npm run db:migrate:staging"} ],
      "needs_you":  [ "npm run db:migrate:live   # live: not in allowed_envs" ],
      "done":       false }

`machine_gate` non-empty → NO human route (31/10/2026, autonomous merge path): the gate
requires a signed 4-way review PASS at depth "deep" with the security reviewer ok/pass
(PASS_REDUCED never counts), and runs `require.verify_commands` (the extra tests) in the
scratch tree after config.verify_commands. Empty `require.verify_commands` on a gated PR
→ the gate stops with verification-readiness (exit 9): fail-closed, never "merge anyway".
`human` non-empty → the gate exits 7. `needs_you` non-empty →
exit 8 unless the gate verifies a head-bound approval. `done` stays false for
compatibility: labels never supply authority. Exit 2 on
unreadable metadata, so the gate fails safe to "human".

Rules, from references/config-schema.json → merge_policy / migrations:
- merge_policy.default "human" → everything waits for a human.
- merge_policy.auto_max_lines (default 0; a positive number is the opt-in cap):
  changed lines (additions + deletions) above a positive cap → human ("big PR —
  please review"). 0, and a missing or null key, are no size cap. Files
  matching merge_policy.size_exclude (default: lockfiles, generated output,
  snapshots) and migration files (migrations.globs) do not count; migration
  lines are reported separately. Per-file counts come from `files[].additions/
  deletions`; without them the PR totals are used.
- merge_policy.machine_gate.categories.<category> (legacy name: merge_policy.always_human.<category>,
  read when machine_gate.categories is absent): any label, path glob, added-line keyword
  or pattern match → machine gate (NOT human). Categories ship as money, auth, schema;
  setting categories replaces them all. A migration PR (migrations.globs) is always
  gated as category "migration" — no opt-out.
  Keywords/patterns skip the added lines of the policy's own tests (POLICY_SELF_TESTS, a fixed list, #747): their
  fixtures are not product code. Labels, paths, migrations, protected_paths and size still count those files.
  Extra tests: merge_policy.machine_gate.verify_commands (every gated PR) plus
  machine_gate.categories.<category>.verify_commands (that category only).
- merge_policy.protected_paths (#605; default DEFAULT_PROTECTED_PATHS, a list replaces it, `[]` turns it off): a PR
  that DELETES (or renames away) a matching file → human, category "delete-protected". The only human-only
  category: a human `done` approves it; an agent cross-review marker does not (super-board-approval.py HUMAN_ONLY).
- migrations: a changed path matching migrations.globs makes this a migration
  PR. Every env in allowed_envs with a command runs (a command of "-" means the
  deploy pipeline applies it: nothing to run). target_env not in allowed_envs, or
  allowed with no command → needs you. migrations.human_steps (any migration PR)
  and `needs-you: <command>` lines in the PR body (any PR) → needs you.
Globs: `**/` any directories (incl. none), `**` anything, `*` within one path
segment, `?` one character.
"""
from __future__ import annotations

import argparse
import json
import re
import sys

DEFAULT_MACHINE_GATE = {
    "money": {
        "labels": ["money", "payments", "billing", "pricing"],
        "paths": ["**/billing/**", "**/payments/**", "**/stripe/**", "**/checkout/**"],
        # Stripe is matched by its real context, not the bare word `stripe.` (#261: `stripe.material`, a colour-stripe variable,
        # sent PR #224 to a person): import/require, api.stripe.com, live keys, a `Stripe(` call. `added` is lower-cased.
        # Go/Java/Kotlin: import SDK (`github.com/stripe/stripe-go`, `import com.stripe.`), gói Go `paymentintent.New(`,
        # `stripe.NewClient(`. Stripe.js: gói `@stripe/…`, `loadStripe(`, `useStripe(`. Mobile: PaymentSheet (iOS/Android/RN),
        # `PaymentConfiguration.init(`, `StripeAPI.`. Tiền ngoài Stripe: Google Play Billing, Unity IAP.
        # ponytail: danh sách theo SDK, receiver tên khác (`stripeService.charges.create(`) vẫn lọt; thêm khi gặp SDK/tên mới.
        "keywords": ["api.stripe.com", "payment_intent", "price_id", "invoice.create",
                     "github.com/stripe/stripe-go", "import com.stripe.", "paymentintent.new(",
                     "stripe.newclient(", "@stripe/", "loadstripe(", "usestripe(", "paymentsheet",
                     "paymentconfiguration.init(", "stripeapi.", "com.android.billingclient", "launchbillingflow(",
                     "unityengine.purchasing", "initiatepurchase("],
        # `require 'stripe'` (Ruby) và `require('stripe')` (Node), giữ dấu đóng để `require('striped-table')` vẫn auto;
        # `new StripeClient(` (Node/PHP v2).
        "patterns": [r"\b(?:import|from)\s+stripe\b", r"from\s+['\"]stripe['\"]", r"require\s*\(?\s*['\"]stripe['\"/]",
                     r"\b[sp]k_live_", r"\bstripe(?:client)?\(",
                     # Lời gọi SDK trong file đã import Stripe từ trước (import không nằm trong diff): `stripe.api_key = …`,
                     # Go `stripe.Key = …`, `stripe.Charge.create(`, `stripeClient.charges.create(`, Ruby `Stripe::Charge.create(`,
                     # PHP `$stripe->charges->create(` / `\Stripe\Charge::create(`, Python `create_async(`. Theo hình dạng
                     # (receiver stripe / stripe_client + phân cách `.` `::` `->` `\` + động từ API + `(`) vì `added` đã hạ
                     # chữ thường. Auto (#261): `stripe.material.depthWrite`, `stripe.mesh.updateMatrix()`, `stripes.delete(`,
                     # `stripeCache.delete(`, `stripedRows.update(`, `key={stripe.key}` (Go chỉ khi gán `stripe.key =`),
                     # `stripe.update(color)`: động từ cần ít nhất một đoạn tài nguyên ở giữa (`+`), SDK không có
                     # `stripe.update(`; lời gọi trực tiếp của Stripe.js có tên riêng (`confirmCardPayment`, `redirectToCheckout`…),
                     # `stripe.confirmSelection(` thì không. `stripe.key = \`row-${i}\`` (template literal JS có `${`) là khoá
                     # danh sách; Go raw string `stripe.Key = \`sk_test_…\`` vẫn là khoá API.
                     r"\bstripe\w*(?:\.|::|->|\\)(?:api_?key|set_?api_?key)\b", r"\bstripe\.key\s*=(?!=)(?!\s*`[^`]*\$\{)",
                     r"\bstripe(?:_?client)?\b(?:(?:\.|::|->|\\)\w+)+(?:\.|::|->|\\)(?:create|retrieve|update|modify|list"
                     r"|del|delete|cancel|capture|confirm|search|construct_?event)(?:_async)?\s*\(",
                     r"\bstripe\.(?:confirm\w*(?:payment|setup)|redirecttocheckout|createpaymentmethod|createtoken"
                     r"|handle(?:card|next)action|retrieve(?:payment|setup)intent|paymentrequest|init\w*checkout)\s*\(",
                     # Go `&stripe.ChargeParams{` (literal luôn có `{`; `&stripe.drawParams)` là con trỏ đồ hoạ), gói Go
                     # `charge.New(`/`refund.New(` theo ranh giới từ (`recharge.New(` vẫn auto), Java khi import nằm ngoài diff:
                     # `PaymentIntent.create(`, `Charge.create(`, `SessionCreateParams`. Không có `.` đứng trước: thuộc tính
                     # của model khác (`battery.charge.create(`) vẫn auto; `stripe.Charge.create(` đã có luật động từ ở trên.
                     r"&stripe\.\w+params\s*\{", r"(?<![\w.])(?:charge|refund)\.new\(",
                     r"(?<![\w.])(?:paymentintent|charge|refund)\.create\(",
                     r"\b(?:paymentintent|charge|refund|session|subscription|invoice|customer|price|product)createparams\b"],
    },
    "auth": {
        "labels": ["auth", "security"],
        "paths": ["**/auth/**", "**/authz/**", "**/permissions/**"],
        "keywords": ["jwt.sign", "bcrypt", "password_hash", "service_role"],
    },
    "schema": {
        "labels": ["schema", "destructive"],
        "paths": [],
        "keywords": ["drop table", "drop column", "truncate table", "rename column", "drop schema"],
        # Valid forms the plain keywords miss: COLUMN / TABLE are optional in `ALTER TABLE t DROP c` and `TRUNCATE t`.
        "patterns": [r"\balter table\b[^;]*\bdrop\b(?! (?:constraint|default|not null|index)\b)",
                     r"\btruncate [a-z_\"`\[]"],
    },
}
DEFAULT_ALWAYS_HUMAN = DEFAULT_MACHINE_GATE   # tên cũ: test/tài liệu cũ còn import tên này
# #747 (quyết định anh Đạt 31/10 16:17): chuỗi tiền / auth / schema làm fixture trong test của chính policy khiến PR sửa
# policy tự bị machine gate. Hằng số cứng, không config/env nào nới; mọi file khác dưới tests/ vẫn bị dò.
POLICY_SELF_TESTS = ["tests/super-board/test_merge_policy_*.sh"]
# #605: xoá các file này chỉ người duyệt (luật chủ repo 28/10). `**/` để khớp cả file trong thư mục con.
DEFAULT_PROTECTED_PATHS = [
    "**/.env*", "**/*.keystore", "**/*.jks", "**/google-services.json", ".agents/regression_matrix.active.json",
    ".agents/local/memory/**", ".agents/local/rules/**",
]   # giữ khớp PROTECTED_DELETE_DEFAULT của universal-agent-devkit/hooks/block-dangerous-git.sh (trừ .git/**: PR không xoá được)
DEFAULT_MIGRATION_GLOBS = [
    "supabase/migrations/**", "prisma/migrations/**", "drizzle/**",
    "**/migrations/*.sql", "db/migrate/**", "alembic/versions/**",
]
DEFAULT_ALLOWED_ENVS = ["test", "staging"]
DEFAULT_AUTO_MAX_LINES = 0
DEFAULT_SIZE_EXCLUDE = [
    # lockfiles
    "**/package-lock.json", "**/yarn.lock", "**/pnpm-lock.yaml", "**/bun.lockb", "**/bun.lock",
    "**/npm-shrinkwrap.json", "**/Cargo.lock", "**/poetry.lock", "**/uv.lock", "**/Pipfile.lock",
    "**/Gemfile.lock", "**/composer.lock", "**/go.sum", "**/Podfile.lock", "**/pubspec.lock",
    # generated output
    "**/generated/**", "**/__generated__/**", "**/*.generated.*", "**/*.gen.*",
    "**/*.min.js", "**/*.min.css", "**/*.map", "**/*.pb.go", "**/*_pb2.py",
    # snapshots
    "**/__snapshots__/**", "**/*.snap",
]


def glob_re(pattern: str) -> re.Pattern:
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif pattern.startswith("**", i):
            out += ".*"; i += 2
        elif pattern[i] == "*":
            out += "[^/]*"; i += 1
        elif pattern[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(pattern[i]); i += 1
    return re.compile("^" + out + "$")


def matches(path: str, globs) -> str | None:
    for g in globs or []:
        if glob_re(g).match(path):
            return g
    return None


def added_text(diff: str) -> str:
    """Added lines of a unified diff, lower-cased, every whitespace run as one space.

    Every `+` line counts, `+++ b/file` headers included: dropping `+++` lines also dropped an added line `++i; ...`
    (`+++i; ...` in the diff), and a header can only add matches (a path holding a keyword goes to a human).
    Collapsing whitespace makes `DROP\\tTABLE`, `DROP  TABLE` or a keyword split over two added lines still match
    `drop table`.
    """
    out = [line[1:] for line in diff.split("\n") if line.startswith("+")]
    return " ".join(" ".join(out).lower().split())


def drop_files(diff: str, globs) -> str:
    """The diff without the file sections whose new path (`+++ b/<path>` before the first hunk) matches a glob.

    A section whose new path cannot be read stays in (fail-closed). Only a real `diff --git ` line starts a section:
    file content always carries a `+`/`-`/` ` prefix, so it cannot fake a header.
    """
    keep = []
    for sec in re.split(r"(?m)^(?=diff --git )", diff):
        new = next((h[4:].strip().strip('"') for h in sec.split("\n@@", 1)[0].split("\n") if h.startswith("+++ ")), "")
        new = new[2:] if new.startswith("b/") else ""
        if not (sec.startswith("diff --git ") and new and matches(new, globs)):
            keep.append(sec)
    return "".join(keep)


def deleted_paths(diff: str) -> list[str]:
    """Paths a unified git diff deletes: `deleted file mode`, `--- a/X` + `+++ /dev/null`, or `rename from X`.

    Read from the diff headers, not `meta.files` (gh gives no change type there). A quoted path (special
    characters) is unquoted only for the plain `"a/..."` form.
    """
    out, old, lines = [], None, diff.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("diff --git "):
            old = None
        elif line.startswith("--- "):
            old = line[4:].strip().strip('"')
            old = old[2:] if old.startswith("a/") else None
            if old and i + 1 < len(lines) and lines[i + 1].startswith("+++ /dev/null"):
                out.append(old)
        elif line.startswith("rename from "):
            out.append(line[len("rename from "):].strip().strip('"'))
        elif line.startswith("deleted file mode") and i > 0:
            # header `diff --git a/X b/X` sits just above; `--- a/X` follows when the file had content.
            head = next((h for h in reversed(lines[:i]) if h.startswith("diff --git ")), "")
            if " b/" in head:
                out.append(head[len("diff --git "):].split(" b/", 1)[0].strip('"').removeprefix("a/"))
    return list(dict.fromkeys(out))


def str_list(value) -> list[str]:
    """Only non-blank strings; anything else is dropped (a gated PR with no usable extra test fails closed in the gate)."""
    if not isinstance(value, list):
        return []
    return [v for v in value if isinstance(v, str) and v.strip()]


def comment_free(text: str) -> str:
    """`DROP/**/TABLE` is a valid DROP TABLE (SQL treats a comment as whitespace): blank `/*...*/` out."""
    return " ".join(re.sub(r"/\*.*?\*/", " ", text).split())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--meta", required=True)
    ap.add_argument("--diff", required=True)
    a = ap.parse_args()

    cfg = json.load(open(a.config))
    try:
        meta = json.load(open(a.meta))
    except ValueError:
        return 2
    if not isinstance(meta, dict) or "files" not in meta:
        return 2
    # newline="" and split("\n") keep a lone CR, VT, FF or NEL inside its added line: universal newlines or
    # splitlines() would cut the text after it into a line without "+", hiding its keywords from always_human.
    # github-read writes UTF-8; the locale's codec would turn U+2028/NEL into non-space text and split a keyword.
    with open(a.diff, encoding="utf-8", errors="replace", newline="") as f:
        diff = f.read()

    labels = {(l.get("name") or "").lower() for l in meta.get("labels") or []}
    paths = [f.get("path") or "" for f in meta.get("files") or []]
    added = added_text(drop_files(diff, POLICY_SELF_TESTS))
    added_nc = comment_free(added)
    body = meta.get("body") or ""

    policy = cfg.get("merge_policy") or {}
    human = []
    if (policy.get("default") or "auto") == "human":
        human.append({"category": "default", "why": "merge_policy.default is \"human\""})
    mig = cfg.get("migrations") or {}
    globs = mig.get("globs") or DEFAULT_MIGRATION_GLOBS
    mig_files = [p for p in paths if matches(p, globs)]

    cap = policy.get("auto_max_lines")
    cap = DEFAULT_AUTO_MAX_LINES if cap is None else int(cap)
    excl = policy.get("size_exclude")
    excl = DEFAULT_SIZE_EXCLUDE if excl is None else excl
    files = meta.get("files") or []
    if files and all("additions" in f for f in files):
        size = mig_lines = 0
        for f in files:
            n = int(f.get("additions") or 0) + int(f.get("deletions") or 0)
            p = f.get("path") or ""
            if p in mig_files:
                mig_lines += n
            elif not matches(p, excl):
                size += n
    else:
        size, mig_lines = int(meta.get("additions") or 0) + int(meta.get("deletions") or 0), 0
    if cap > 0 and size > cap:
        extra = f" (+{mig_lines} migration lines counted separately)" if mig_lines else ""
        human.append({"category": "size",
                      "why": f"big PR — please review: {size} changed lines > auto_max_lines {cap}{extra}"})
    # 31/10/2026: money / auth / schema / migration no longer route to a human. They go through an extra MACHINE gate
    # (deep 4-way review + security reviewer + extra tests), enforced by super-board-merge-gate.sh; fail-closed there.
    gate_cfg = policy.get("machine_gate") if isinstance(policy.get("machine_gate"), dict) else {}
    if isinstance(gate_cfg.get("categories"), dict):
        always = gate_cfg["categories"]
    elif isinstance(policy.get("always_human"), dict):
        always = policy["always_human"]
    else:
        always = DEFAULT_MACHINE_GATE
    machine, extra_tests = [], str_list(gate_cfg.get("verify_commands"))
    for cat, rule in always.items():
        rule = rule if isinstance(rule, dict) else {}
        hit = next((f"label {l}" for l in rule.get("labels") or [] if l.lower() in labels), None)
        if not hit:
            hit = next((f"path {p} (matches {g})" for p in paths
                        for g in [matches(p, rule.get("paths"))] if g), None)
        if not hit:
            hit = next((f"keyword \"{k}\" in an added line" for k in rule.get("keywords") or []
                        if " ".join(k.lower().split()) in added or " ".join(k.lower().split()) in added_nc), None)
        if not hit:
            hit = next((f"pattern \"{r}\" in an added line" for r in rule.get("patterns") or []
                        if re.search(r, added) or re.search(r, added_nc)), None)
        if hit:
            machine.append({"category": cat, "why": hit})
            extra_tests += str_list(rule.get("verify_commands"))
    if mig_files:
        shown = ", ".join(mig_files[:5]) + (f" (+{len(mig_files) - 5} more)" if len(mig_files) > 5 else "")
        machine.append({"category": "migration", "why": f"migration files: {shown}"})
    extra_tests = list(dict.fromkeys(extra_tests))
    require = {"deep_review": bool(machine), "security_reviewer": bool(machine),
               "verify_commands": extra_tests if machine else []}
    protected = policy.get("protected_paths")
    protected = DEFAULT_PROTECTED_PATHS if protected is None else protected
    gone = next((f"deletes {p} (matches {g})" for p in deleted_paths(diff) for g in [matches(p, protected)] if g), None)
    if gone:
        human.append({"category": "delete-protected", "why": gone})

    run, needs = [], []
    if mig_files:
        allowed = mig.get("allowed_envs")
        allowed = DEFAULT_ALLOWED_ENVS if allowed is None else allowed
        base = cfg.get("base_branch") or "main"
        target = mig.get("target_env") or ("live" if base in ("main", "master") else "staging")
        cmds = mig.get("commands") or {}
        for env in allowed:
            cmd = (cmds.get(env) or "").strip()
            if cmd and cmd != "-":
                run.append({"env": env, "cmd": cmd})
            elif env == target and not cmd:
                needs.append(f"<your {env} migrate command>   # {env}: allowed, but migrations.commands.{env} is not set")
        if target not in allowed:
            cmd = (cmds.get(target) or "").strip()
            if cmd != "-":
                needs.append(f"{cmd or '<your ' + target + ' migrate command>'}   # {target}: the base deploys here and it is not in allowed_envs")
        needs += [str(s) for s in mig.get("human_steps") or []]
    for line in body.splitlines():
        m = re.match(r"^\s*(?:[-*]\s*)?needs-you:\s*(.+?)\s*$", line, re.I)
        if m and m.group(1).lower() != "done":
            needs.append(m.group(1).strip("`"))

    print(json.dumps({"human": human, "machine_gate": machine, "require": require, "migrations": mig_files,
                      "run": run, "needs_you": needs, "done": False}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
