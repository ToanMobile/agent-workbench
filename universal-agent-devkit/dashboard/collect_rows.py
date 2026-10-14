"""Read-only snapshot of how the DevKit is wired in each default repo (hooks, skills, MCP servers, tools).

Writes, next to this file:
  checks.json        one table, columns: repo, area, group, item, kind, state, trigger, detail
                     (area="hook" rows also carry `order`: place in the kit template's chain, 1000 for a hook the kit does not declare)
  workflow-map.html  the same table rendered by workflow-map.page.html, openable as a plain file
usage: python3 collect_rows.py
The Artifact dashboard uses checks.json and workflow-map.page.html directly (see README in the commit).
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
KIT = HERE.parent
REPOS = {
    "agent-workbench": "/Volumes/Data/Toan/agent-workbench",
    "GeelyEx2": "/Volumes/Data/Toan/GeelyEx2",
    "OfficeReader": "/Volumes/Data/Toan/OfficeReader/OfficeReader",
    "Goods": "/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D",
    "Neighbours-From-Hell": "/Volumes/Data/Toan/Game/Neighbours-From-Hell",
}
# user requirement 2026-10-13, per repo: MCP servers that must run there (anything else is optional)
BASE_MCPS = ["codebase-memory-mcp", "context7", "agentmemory"]
ALL_MCPS = BASE_MCPS + ["play-store", "replicant-mcp"]
REQUIRED_MCPS = {
    "agent-workbench": BASE_MCPS,                    # no replicant-mcp, no play-store: it has no app or device
    "GeelyEx2": BASE_MCPS + ["replicant-mcp"],       # no play-store
    "OfficeReader": ALL_MCPS,
    "Goods": ALL_MCPS,
    "Neighbours-From-Hell": ALL_MCPS,
}
TOOLS = ["ocr", "agent-kit", "codebase-memory-mcp", "npx", "uvx", "git", "python3"]
STAGE_ORDER = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Notification", "SessionEnd"]


def warn(msg):
    sys.stderr.write("collect_rows: " + msg + "\n")


def jload(path):
    p = Path(path)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError) as e:
        warn(f"cannot read {p}: {e}")
        return None


def run(cmd, cwd=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=20).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def hook_rows(settings):
    out = []
    for ev, groups in ((settings or {}).get("hooks") or {}).items():
        for g in groups:
            for h in g.get("hooks", []):
                m = re.search(r"([\w.\-]+\.(?:sh|py))", h.get("command", ""))
                out.append((ev, g.get("matcher") or "", m.group(1) if m else h.get("command", "")[:40]))
    return out


def hook_blurb(script):
    """first '# name — text' header line of the kit's hook script ('' for a repo-local hook the kit does not ship)"""
    if not (KIT / "hooks" / script).exists():
        return ""
    try:
        for line in (KIT / "hooks" / script).read_text(errors="ignore").splitlines()[:12]:
            m = re.match(r"#\s*" + re.escape(script) + r"\s*[—-]+\s*(.+)", line)
            if m:
                return m.group(1).strip()[:160]
    except OSError as e:
        warn(f"cannot read hook {script}: {e}")
    return ""


def mentions(root, needle):
    hits = set()
    for p in Path(root).rglob("*"):
        if p.suffix in (".sh", ".py") and p.is_file() and "tests" not in p.parts and "__pycache__" not in p.parts:
            try:
                if needle in p.read_text(errors="ignore"):
                    hits.add(p.name)
            except OSError as e:
                warn(f"cannot scan {p}: {e}")
    return sorted(hits)


tmpl = hook_rows(jload(KIT / "templates/claude_settings.json"))
kit_skills = sorted(p.name for p in (KIT / "skills").iterdir() if p.is_dir())
hooks_dir_mentions = {}
for s in kit_skills:
    hooks_dir_mentions[s] = (mentions(KIT / "hooks", s), mentions(KIT / "scripts/context", s))


def skill_trigger(skill):
    in_hooks, in_ctx = hooks_dir_mentions[skill]
    parts = []
    if in_hooks:
        parts.append("named in hook: " + ", ".join(in_hooks[:3]))
    if in_ctx:
        parts.append("prompt suggestion: " + ", ".join(in_ctx[:2]))
    return " + ".join(parts) if parts else "agent's own choice only"


# ---- the lifecycle of one task, in the order AGENTS.md ("Every prompt") and the Stop hooks apply it ----
PHASES = [
    ("p1", "Nạp ngữ cảnh & luật", "Mở phiên: nạp AGENTS.md, luật theo profile, luật riêng của repo và bài học cũ; mỗi thư mục chỉ một phiên được ghi."),
    ("p2", "Hiểu yêu cầu", "Mỗi prompt được gắn loại việc, bẫy từng gặp và skill gợi ý trước khi agent làm."),
    ("p3", "Trước khi sửa", "Phải đọc file trước khi sửa; không ghi vào thư mục phiên khác đang giữ."),
    ("p4", "Viết code", "Chặn lệnh git nguy hiểm, sửa đi sửa lại một file không có bằng chứng, chú thích khẳng định điều chưa kiểm."),
    ("p5", "Test RED→GREEN", "Test phải đỏ trước khi sửa và xanh sau đó; ma trận hồi quy chạy khi dừng."),
    ("p6", "Review", "Thay đổi code phải được review bằng ngữ cảnh mới trước khi dừng."),
    ("p7", "Nghiệm thu", "Cổng post-fix phải exit 0; repo có màn hình thì phải có ảnh chứng minh."),
    ("p8", "Chốt & giao", "Kiểm câu báo cáo, bảo mật, repo khác, worktree, rồi git hook trước commit/push."),
]
HOOK_VI = {
    "session_context.sh": "nạp ngữ cảnh đầu phiên (profile, bài học, trạng thái)",
    "session_lock.sh": "một thư mục — một phiên; phiên thứ hai chỉ được đọc",
    "prompt_context.sh": "gắn loại việc, bẫy từng gặp và skill gợi ý vào prompt",
    "precode_gate.sh": "cổng duy nhất chạy TRƯỚC khi viết code",
    "read_ledger.sh": "ghi file đã đọc, để sửa file phải đọc trước",
    "worktree_guard.sh": "chặn ghi nhầm vào checkout hoặc worktree không phải của phiên",
    "block-dangerous-git.sh": "chặn lệnh git nguy hiểm (--no-verify, force...)",
    "bash_write_ledger.sh": "ghi khung thời gian của mỗi lệnh Bash, để cổng Stop biết file nào do phiên này ghi",
    "churn_guard.sh": "sửa cùng một file lần thứ ba mà chưa có bằng chứng mới thì cảnh báo (không chặn)",
    "comment_claim_guard.sh": "chú thích không được khẳng định điều chưa kiểm chứng",
    "hardware_safety_gate.sh": "chặn lệnh có thể làm hỏng thiết bị phần cứng",
    "regression_gate.sh": "checklist hồi quy phải xanh khi dừng",
    "test_evidence_gate.sh": "nói 'test pass' hay 'đã fix' phải có kết quả runner; test mới phải từng đỏ",
    "testsourceset_gate.sh": "biên dịch bộ test của mọi module khi dừng",
    "review_gate.sh": "thay đổi code phải qua một lần review ngữ cảnh mới mới được dừng",
    "proof_gate.sh": "câu mở bằng XONG phải kèm ảnh nghiệm thu của lượt này",
    "claim_check.sh": "chống bịa: khẳng định phải có bằng chứng",
    "security_gate.sh": "review bảo mật khi thay đổi chạm vùng nhạy cảm",
    "foreign_repo_gate.sh": "cổng đã chạy nhầm repo: phiên sửa file repo khác",
    "worktree_merge_gate.sh": "worktree phải được gộp vào nhánh chính rồi xoá",
}
SKILL_VI = {
    "context-enricher": "làm giàu yêu cầu ngắn thành hồ sơ kỹ thuật",
    "spec-driven-development": "viết spec trước khi code",
    "grill-plan": "phản biện kế hoạch trước khi code",
    "codebase-memory": "tra đồ thị mã nguồn thay vì đoán",
    "incremental-implementation": "làm từng bước nhỏ, kiểm từng bước",
    "tdd-workflow": "quy trình test RED→GREEN",
    "fixbugs": "chẩn đoán và sửa bug có cặp test",
    "qa-review": "chất vấn diff, sinh tiêu chí chấp nhận",
    "open-code-review": "review diff bằng ocr (Alibaba)",
    "giao": "giao việc cho Antigravity rồi audit",
    "verification-before-completion": "kiểm chứng trước khi báo xong",
    "session-handoff": "ghi bàn giao khi kết thúc phiên",
}
# (kind, id, label override)
FLOW = {
    "p1": [("hook", "session_context.sh"), ("hook", "session_lock.sh"), ("file", "AGENTS.md", "AGENTS.md (luật chung)"),
           ("file", ".agents/context/profile-rules.md", "Luật theo profile"), ("file", ".agents/context/rules-index.md", "Mục lục luật riêng"),
           ("rules", ""), ("instincts", ""), ("mcp", "codebase-memory-mcp"), ("mcp", "agentmemory")],
    "p2": [("hook", "prompt_context.sh"), ("skill", "context-enricher"), ("skill", "spec-driven-development"), ("skill", "grill-plan")],
    "p3": [("hook", "precode_gate.sh"), ("hook", "read_ledger.sh"), ("hook", "worktree_guard.sh"), ("skill", "codebase-memory")],
    "p4": [("hook", "block-dangerous-git.sh"), ("hook", "bash_write_ledger.sh"), ("hook", "churn_guard.sh"),
           ("hook", "comment_claim_guard.sh"), ("hook", "hardware_safety_gate.sh"), ("skill", "incremental-implementation")],
    "p5": [("skill", "tdd-workflow"), ("skill", "fixbugs"), ("matrix", ""), ("hook", "regression_gate.sh"),
           ("hook", "test_evidence_gate.sh"), ("hook", "testsourceset_gate.sh")],
    "p6": [("hook", "review_gate.sh"), ("skill", "qa-review"), ("skill", "open-code-review"), ("tool", "ocr"),
           ("agent", "principal-code-reviewer"), ("skill", "giao")],
    "p7": [("file", ".agents/devkit/bin/post-fix-gate.py", "Cổng post-fix (post-fix-gate.py)"), ("hook", "proof_gate.sh"),
           ("proof", ""), ("skill", "verification-before-completion")],
    "p8": [("hook", "claim_check.sh"), ("hook", "security_gate.sh"), ("hook", "foreign_repo_gate.sh"), ("hook", "worktree_merge_gate.sh"),
           ("githook", "pre-commit"), ("githook", "pre-push"), ("githook", "commit-msg"), ("skill", "session-handoff")],
}
SCREEN_PROFILES = {"android", "automotive", "game", "web", "ios"}


def git_hook_exists(repo, name):
    rel = run(["git", "rev-parse", "--git-path", "hooks/" + name], cwd=repo)
    f = Path(rel) if rel.startswith("/") else Path(repo) / rel
    return f.exists()


rows = []
ocr_ver = run(["ocr", "version"]).splitlines()[0] if shutil.which("ocr") else ""

for name, path in REPOS.items():
    r = Path(path)
    add = lambda area, group, item, state, trigger="", detail="", kind="", **extra: rows.append(
        {"repo": name, "area": area, "group": group, "item": item, "kind": kind, "state": state,
         "trigger": trigger, "detail": detail, **extra})

    prof = jload(r / ".agents/active-profile.json") or {}
    pid = prof.get("profile", "universal")
    meta = jload(KIT / "profiles" / pid / "profile.json") or {}
    add("profile", "profile", pid, "ok", "", f"{len(prof.get('active_councils', []))} councils")

    # --- workflow hooks (Claude) vs kit template
    have = hook_rows(jload(r / ".claude/settings.json"))
    have_set = set(have)
    for ev, mt, sc in sorted(set(tmpl) | have_set, key=lambda t: (STAGE_ORDER.index(t[0]) if t[0] in STAGE_ORDER else 99, t[2])):
        f = r / ".claude/hooks" / sc
        inline = not re.search(r"\.(sh|py)$", sc)
        if (ev, mt, sc) not in have_set:
            state = "missing"
        elif inline:
            state = "local"
        elif not f.exists():
            state = "broken"
        elif (ev, mt, sc) not in tmpl:
            state = "local"
        else:
            state = "ok"
        # order = place in the kit template's chain; a hook the kit does not declare gets 1000+ (the page lists it apart)
        order = tmpl.index((ev, mt, sc)) if (ev, mt, sc) in tmpl else 1000
        add("hook", ev, sc, state, mt or "any tool", hook_blurb(sc), order=order)

    # --- skills
    exclude = set(meta.get("exclude_skills", []))
    sdir = r / ".agents/skills"
    present, broken = set(), set()
    if sdir.exists():
        for p in sdir.iterdir():
            if p.is_symlink() and not p.exists():
                broken.add(p.name)
            elif p.is_dir():
                present.add(p.name)
    for s in kit_skills:
        if s in exclude:
            state = "excluded"
        elif s in broken:
            state = "broken"
        elif s in present:
            state = "ok"
        else:
            state = "missing"
        add("skill", "kit skill", s, state, skill_trigger(s), "excluded by profile " + pid if state == "excluded" else "")
    for s in sorted(present - set(kit_skills)):
        add("skill", "project skill", s, "local", "", "not from the kit")

    # --- MCP
    mcp = (jload(r / ".mcp.json") or {}).get("mcpServers", {})
    local = jload(r / ".claude/settings.local.json") or {}
    enabled, disabled = set(local.get("enabledMcpjsonServers", [])), set(local.get("disabledMcpjsonServers", []))
    all_ok = bool(local.get("enableAllProjectMcpServers"))
    need = REQUIRED_MCPS[name]
    for m in sorted(set(mcp) | set(ALL_MCPS)):
        req = m in need
        if m not in mcp:
            state, det = ("missing", "chưa khai báo trong .mcp.json") if req else ("na", "repo này không cần server này")
        elif m in disabled:
            state, det = "off", "đã khai báo nhưng bị tắt trong settings.local.json"
        elif m in enabled or all_ok:
            state, det = "ok", "đã khai báo và bật"
        else:
            state, det = "off", "đã khai báo nhưng chưa được bật"
        add("mcp", "required" if req else "extra", m, state, "tool call", det)

    # --- tools on PATH
    for t in TOOLS:
        p = shutil.which(t)
        det = (ocr_ver if t == "ocr" and p else p) or "not on PATH"
        if t == "ocr" and p:
            det += " | runs in repo: " + ("yes" if run(["ocr", "version"], cwd=path) else "NO")
        trig = ""
        if t == "ocr":
            runners = [h for h in mentions(KIT / "hooks", "ocr review") + mentions(KIT / "hooks", "ocr scan") + mentions(KIT / "hooks", "ocr delegate")]
            trig = ("hook chạy: " + ", ".join(sorted(set(runners)))) if runners else "không hook nào chạy lệnh này"
        add("tool", "cli", t, "ok" if p else "missing", trig, det)

    # --- the lifecycle: for each phase, which component is wired in this repo and how it fires
    hooks_ok, hooks_bad = {}, set()
    for ev, mt, sc in have:
        hooks_ok[sc] = True
    skill_state = {x["item"]: x for x in rows if x["repo"] == name and x["area"] == "skill"}
    mcp_state = {x["item"]: x for x in rows if x["repo"] == name and x["area"] == "mcp"}
    tool_state = {x["item"]: x for x in rows if x["repo"] == name and x["area"] == "tool"}
    local_rules = sorted((r / ".agents/local/rules").glob("*.md")) if (r / ".agents/local/rules").exists() else []
    instincts = len(set(re.findall(r"INSTINCT-\d+", (r / ".agents/instincts.md").read_text(errors="ignore")))) if (r / ".agents/instincts.md").exists() else 0
    matrix = (jload(r / ".agents/regression_matrix.active.json") or {}).get("rules", [])
    agents_dir = r / ".claude/agents"
    for ph, _, _ in PHASES:
        for spec in FLOW[ph]:
            kind, ident = spec[0], spec[1]
            label = spec[2] if len(spec) > 2 else ident
            trig, state, detail, vkind = "", "ok", "", kind
            if kind == "hook":
                vkind, trig, detail = "hook", "hook tự chạy", HOOK_VI.get(ident, "")
                state = "ok" if ident in hooks_ok and (r / ".claude/hooks" / ident).exists() else ("broken" if ident in hooks_ok else "missing")
            elif kind == "skill":
                sx = skill_state.get(ident, {})
                vkind = "skill"
                trig = "gợi ý trong prompt" if "prompt suggestion" in sx.get("trigger", "") else "agent tự chọn"
                state = sx.get("state", "missing")
                detail = SKILL_VI.get(ident, "")
            elif kind == "file":
                vkind, trig = "luật" if "rules" in ident or ident == "AGENTS.md" else "công cụ", "nạp vào phiên" if "rules" in ident or ident == "AGENTS.md" else "chạy khi nghiệm thu"
                state = "ok" if (r / ident).exists() else "missing"
            elif kind == "rules":
                label, vkind, trig = "Luật riêng của repo (.agents/local/rules)", "luật", "nạp vào phiên"
                state, detail = ("ok", f"{len(local_rules)} file luật") if local_rules else ("empty", "chưa có file luật riêng nào")
            elif kind == "instincts":
                label, vkind, trig = "Bài học từ bug cũ (instincts)", "luật", "gợi ý trong prompt"
                state, detail = ("ok", f"{instincts} bài học") if instincts else ("empty", "chưa có bài học nào")
            elif kind == "mcp":
                vkind, trig = "MCP", "gọi khi agent cần"
                mx = mcp_state.get(ident, {})
                state, detail = mx.get("state", "missing"), mx.get("detail", "")
            elif kind == "tool":
                vkind = "công cụ"
                tx = tool_state.get(ident, {})
                state, detail = tx.get("state", "missing"), tx.get("detail", "")
                trig = "agent tự chọn" if ident == "ocr" else "agent tự chọn"
                if ident == "ocr" and "không hook" in tx.get("trigger", ""):
                    detail = "không hook nào chạy ocr, chỉ chạy khi agent tự gọi"
            elif kind == "matrix":
                label, vkind, trig = "Ma trận hồi quy (regression_matrix.active.json)", "test", "chạy khi dừng"
                state, detail = ("ok", f"{len(matrix)} quy tắc hồi quy") if matrix else ("empty", "ma trận chưa có quy tắc nào")
            elif kind == "agent":
                vkind, trig = "subagent", "agent tự gọi"
                n = len(list(agents_dir.glob("*.md"))) if agents_dir.exists() else 0
                state = "ok" if (agents_dir / (ident + ".md")).exists() else "missing"
                detail = f"{n} subagent trong .claude/agents"
            elif kind == "githook":
                label, vkind, trig = "git " + ident, "git", "git tự chạy"
                state = "ok" if git_hook_exists(path, ident) else "missing"
            elif kind == "proof":
                label, vkind, trig = "Ảnh nghiệm thu (proof-capture.py)", "công cụ", "bắt buộc khi có màn hình"
                if pid in SCREEN_PROFILES:
                    state = "ok" if (r / ".agents/devkit/bin/proof-capture.py").exists() else "missing"
                else:
                    state, detail = "na", f"profile {pid}: không có màn hình"
            add("flow", ph, label, state, trig, detail, vkind)

    # --- worktrees left behind
    for wt in run(["git", "worktree", "list"], cwd=path).splitlines()[1:]:
        if Path(wt.split()[0]).resolve() == KIT.parent:  # the worktree this script runs in is not left behind
            continue
        add("worktree", "unmerged?", wt.split()[0].rsplit("/", 1)[-1], "warn", "", wt.split()[0])

STANDALONE_HEAD = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>DevKit workflow map</title>
<style>
:root { --color-fg:#1f2328; --color-fg-muted:#59636e; --color-bg:#f6f8fa; --color-panel:#ffffff; --color-border-line:#d8dee4;
  --color-ok:#1a7f4b; --color-warn:#9a6700; --color-bad:#c62828; --cds-radius:8px; --cds-pad-lg:16px;
  --cds-gap-xs:4px; --cds-gap-sm:8px; --cds-gap-md:12px; --cds-gap-lg:16px; --cds-gap-xl:28px;
  --cds-font-size-caption:12px; --cds-font-size-body:14px; --cds-font-size-heading:16px; --cds-font-size-title:28px;
  --cds-font-weight-medium:500; --font-anthropic-sans:system-ui,-apple-system,"Segoe UI",sans-serif;
  --font-anthropic-serif:Georgia,"Times New Roman",serif; color-scheme: light; }
@media (prefers-color-scheme: dark) { :root { --color-fg:#e6edf3; --color-fg-muted:#9aa4af; --color-bg:#0d1117;
  --color-panel:#151b23; --color-border-line:#2d333b; --color-ok:#56d364; --color-warn:#e3b341; --color-bad:#ff7b72; color-scheme: dark; } }
body { margin:0; padding:24px 16px; background:var(--color-bg); color:var(--color-fg); font:14px var(--font-anthropic-sans); }
</style></head><body>
<div id="dash-root">
"""
STANDALONE_TAIL = "</div></body></html>\n"

(HERE / "checks.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1) + "\n")
embedded = json.dumps(rows, ensure_ascii=False).replace("</", "<\\/")
html = (STANDALONE_HEAD
        + '<script id="checks-data" type="application/json">' + embedded + "</script>\n"
        + "<script>\n" + (HERE / "dash_shim.js").read_text() + "</script>\n"
        + (HERE / "workflow-map.page.html").read_text()
        + STANDALONE_TAIL)
(HERE / "workflow-map.html").write_text(html)
print(len(rows), "rows ->", HERE / "checks.json", "and", HERE / "workflow-map.html")
