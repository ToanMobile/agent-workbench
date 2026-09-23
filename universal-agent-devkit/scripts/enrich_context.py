#!/usr/bin/env python3
# enrich_context.py — Autonomous Prompt Context & Intent Enrichment Engine
# Transforms a brief user prompt into a 5-dimensional technical specification dossier.

import sys
import os
import json
import re
import subprocess

# Mọi dạng ID: INSTINCT-001, INSTINCT-IOS-01, INSTINCT-VOICE-02, INSTINCT-AUTO (bản cũ của post-fix-gate --record-lesson; nay ghi INSTINCT-NNN)
INSTINCT_BLOCK_RE = re.compile(r"(^### \[(INSTINCT-[A-Za-z0-9_-]+)\].*?)(?=^### \[INSTINCT-|\Z)", re.DOTALL | re.MULTILINE)


def find_project_root(start="."):
    try:
        res = subprocess.run(["git", "-C", start, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=5)
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.abspath(start)


def instinct_sources(devkit_root, project_root):
    """Dự án trước (bài học thật của dự án), rồi tới DevKit; bỏ trùng theo realpath."""
    cands = []
    for root in (project_root, devkit_root):
        if root:
            cands.append(os.path.join(root, ".agents", "instincts.md"))
            cands.append(os.path.join(root, ".agents", "active-profile", "instincts.md"))
    seen, out = set(), []
    for c in cands:
        if os.path.isfile(c):
            rp = os.path.realpath(c)
            if rp not in seen:
                seen.add(rp)
                out.append(c)
    return out


# Words too common in requests to say anything about WHICH trap applies.
STOPWORDS = {
    "sửa", "lỗi", "giúp", "tạo", "làm", "cho", "vào", "khi", "bị", "của", "và", "các", "những",
    "này", "đó", "với", "trong", "không", "được", "thì", "là", "có", "một", "để", "lại", "hãy",
    "tôi", "anh", "em", "mình", "bạn", "nữa", "rồi", "đang", "cần", "muốn", "thêm", "xem", "lần",
    "the", "and", "for", "with", "this", "that", "fix", "bug", "please", "add", "make", "into",
    "from", "not", "are", "was", "can", "use", "new", "all",
    "cách", "động", "hoạt", "giải", "thích", "người", "dùng", "việc", "như", "thế", "nào", "sao",
    "hiện", "tại", "sau", "trước", "vẫn", "luôn", "hết", "đúng", "sai", "code", "file", "app",
}

# Technical words the trap entries use for each detected intent — the request says
# "bấm 2 lần", the entry says "double-click / debounce".
INTENT_TERMS = {
    "UI_INTERACTION": {"click", "debounce", "double", "touch", "48dp", "isloading", "issubmitting"},
    "PERFORMANCE_AND_RESPONSIVENESS": {"main", "thread", "anr", "leak", "blocking", "o"},
    "NETWORK_AND_RESILIENCE": {"timeout", "idempotency", "retry", "backoff"},
    "DEPRECATION_MIGRATION": {"migration", "schema"},
}


def enrich_prompt(prompt, devkit_root=".", project_root=None):
    dossier = {
        "dossier_type": "5D_CONTEXT_DOSSIER",
        "user_prompt": prompt,
        "active_profile": "universal",
        "detected_intents": [],
        "codebase_queries": [],
        "matched_instincts": [],
        "injected_nfrs": [],
        "paired_oracle_spec": {},
        "recommended_skills": []
    }

    # 1. Read Active Profile
    active_profile_file = os.path.join(project_root or devkit_root, ".active-profile.json")
    if not os.path.exists(active_profile_file):
        active_profile_file = os.path.join(devkit_root, ".active-profile.json")
    if os.path.exists(active_profile_file):
        try:
            with open(active_profile_file, "r") as f:
                prof_data = json.load(f)
                dossier["active_profile"] = prof_data.get("profile", "universal")
        except Exception:
            pass

    p_lower = prompt.lower()

    # 2. Detect Intents & Recommend Skills
    if any(k in p_lower for k in ["lỗi", "bug", "crash", "văng", "hỏng", "fail", "sửa", "chết", "die"]):
        dossier["detected_intents"].append("BUG_FIX")
        dossier["recommended_skills"].extend(["fixbugs", "tdd-workflow", "verification-before-completion"])
        dossier["paired_oracle_spec"] = {
            "required": True,
            "rule": "PAIRED EXECUTABLE ORACLE: Must observe test RED before editing code, then GREEN after.",
            "compile_only_permitted_if": "The root defect itself is a compilation/build failure."
        }

    if any(k in p_lower for k in ["nút", "click", "bấm", "giao diện", "ui", "màn hình", "layout", "button", "tap"]):
        dossier["detected_intents"].append("UI_INTERACTION")
        dossier["injected_nfrs"].append("Debounce >= 1000ms + Instant Disable on 1st click + Loading indicator.")
        dossier["injected_nfrs"].append("Touch Target >= 48dp (Mobile) / >= 44px (Web).")
        dossier["injected_nfrs"].append("Design Tokens adherence: Semantic colors from DESIGN.md.")
        if dossier["active_profile"] == "android":
            dossier["recommended_skills"].append("android-real-device-qa")

    if any(k in p_lower for k in ["lag", "chậm", "đơ", "anr", "tối ưu", "hiệu năng", "fps", "treo", "freeze", "xoay"]):
        dossier["detected_intents"].append("PERFORMANCE_AND_RESPONSIVENESS")
        dossier["injected_nfrs"].append("Non-blocking Main Thread: Move heavy work/IO to background dispatchers.")
        dossier["injected_nfrs"].append("Algorithm complexity: O(1) lookup via Map/Set; avoid O(N^2) dynamic loops.")
        dossier["injected_nfrs"].append("Zero memory leaks: unregister listeners/observers upon lifecycle destroy.")
        dossier["recommended_skills"].append("observability-instrumentation")
        if dossier["active_profile"] == "android":
            dossier["recommended_skills"].append("android-real-device-qa")

    if any(k in p_lower for k in ["mạng", "api", "gọi", "request", "server", "timeout", "offline", "sync"]):
        dossier["detected_intents"].append("NETWORK_AND_RESILIENCE")
        dossier["injected_nfrs"].append("Explicit Timeouts: Connect <= 10s, Read <= 15s.")
        dossier["injected_nfrs"].append("Idempotency-Key (UUIDv4) for state-mutating requests (POST/PUT).")
        dossier["injected_nfrs"].append("Exponential backoff with jitter for retries.")

    if any(k in p_lower for k in ["refactor", "thiết kế", "kiến trúc", "module", "tách", "interface"]):
        dossier["detected_intents"].append("ARCHITECTURE_REFACTOR")
        dossier["recommended_skills"].extend(["grill-plan", "deep-module-design", "documentation-and-adrs", "incremental-implementation"])

    if any(k in p_lower for k in ["xóa", "bỏ", "deprecate", "sunset", "chuyển sang", "migrate"]):
        dossier["detected_intents"].append("DEPRECATION_MIGRATION")
        dossier["recommended_skills"].extend(["deprecation-migration", "documentation-and-adrs"])

    if any(k in p_lower for k in ["giao", "antigravity", "pm", "phân công"]):
        dossier["detected_intents"].append("DUAL_AGENT_DELEGATION")
        dossier["recommended_skills"].append("giao")

    if any(k in p_lower for k in ["crashlytics", "traces.txt", "stacktrace", "sập app", "triage"]):
        dossier["detected_intents"].append("CRASH_TRIAGE")
        dossier["recommended_skills"].append("fixbugs")

    if any(k in p_lower for k in ["conflict", "xung đột", "merge", "rebase", "cherry-pick"]):
        dossier["detected_intents"].append("MERGE_CONFLICT")
        dossier["recommended_skills"].append("merge-conflict-resolver")

    if any(k in p_lower for k in ["release", "deploy", "đóng gói", "apk", "aab", "publish", "phát hành"]):
        dossier["detected_intents"].append("RELEASE_DEPLOY")
        dossier["recommended_skills"].extend(["deploy", "qc", "verification-before-completion"])

    if any(k in p_lower for k in ["review", "pr", "pull request", "soát diff", "chất vấn", "nghiệm thu"]):
        dossier["detected_intents"].append("CODE_AND_QA_REVIEW")
        dossier["recommended_skills"].extend(["qa-review", "open-code-review", "verification-before-completion"])

    if any(k in p_lower for k in ["spec", "tính năng mới", "feature lớn", "yêu cầu mới"]):
        dossier["detected_intents"].append("SPEC_PLANNING")
        dossier["recommended_skills"].extend(["spec-driven-development", "grill-plan", "documentation-and-adrs"])

    if any(k in p_lower for k in ["vỡ layout", "tràn khung", "lệch giao diện", "screenshot", "chụp màn"]):
        dossier["detected_intents"].append("VISUAL_QA")
        dossier["recommended_skills"].append("qa-visual")

    if any(k in p_lower for k in ["tìm hàm", "ai gọi", "luồng gọi", "đồ thị", "graph"]):
        dossier["detected_intents"].append("CODEBASE_EXPLORE")
        dossier["recommended_skills"].append("codebase-memory")

    if any(k in p_lower for k in ["bàn giao", "checkpoint", "nén ngữ cảnh", "compact", "phiên dài"]):
        dossier["detected_intents"].append("SESSION_HANDOFF")
        dossier["recommended_skills"].append("session-handoff")

    if any(k in p_lower for k in ["viết skill", "tạo skill", "chuẩn hóa skill", "rule mới"]):
        dossier["detected_intents"].append("SKILL_AUTHORING")
        dossier["recommended_skills"].append("writing-skills")

    # Fallback default intent if none matched
    if not dossier["detected_intents"]:
        dossier["detected_intents"].append("GENERAL_TASK")
        dossier["recommended_skills"].append("incremental-implementation")

    # Injected Core NFRs that apply to ALL tasks
    dossier["injected_nfrs"].append("Anti-Laziness: Strictly zero placeholder code (// ... existing code ...).")
    dossier["injected_nfrs"].append("Structured Logging: Zero raw console.log/println; mask 100% PII (Token/Password/ID).")
    dossier["injected_nfrs"].append("Anti-Swallowing: Zero empty catch/except blocks.")

    # 3. Match Instincts from instincts.md — ranked by how many of the prompt's
    #    meaningful words (stopwords like "sửa", "lỗi", "bị" dropped) the entry shares,
    #    title hits counting double. Template placeholders ([INSTINCT-XXX]) and entries
    #    inside HTML comments are never matched.
    keywords = {w for w in re.findall(r"[\w$]+", p_lower) if len(w) >= 3 and w not in STOPWORDS}
    for intent in dossier["detected_intents"]:
        keywords |= INTENT_TERMS.get(intent, set())
    entries, seen_titles = [], set()
    for instincts_file in instinct_sources(devkit_root, project_root):
        try:
            with open(instincts_file, "r", encoding="utf-8") as f:
                content = f.read()
        except (OSError, UnicodeDecodeError) as e:
            print(f"warning: không đọc được {instincts_file}: {e}", file=sys.stderr)
            continue
        visible = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), content, flags=re.DOTALL)
        for m in INSTINCT_BLOCK_RE.finditer(visible):
            full_block, inst_id = m.group(1), m.group(2)
            if "XXX" in inst_id:
                continue
            header_line = full_block.strip().split("\n")[0].replace("### ", "")
            if header_line in seen_titles:
                continue  # the same trap copied into the profile's instincts.md too
            seen_titles.add(header_line)
            entries.append((header_line, set(re.findall(r"[\w$]+", header_line.lower())),
                            set(re.findall(r"[\w$]+", full_block.lower())),
                            instincts_file, visible.count("\n", 0, m.start()) + 1))
    # A word found in many entries (Vietnamese syllables like "cách", "động") says
    # nothing about WHICH trap applies: only words in at most a quarter of the
    # entries (min 2) score, and an entry needs 2+ points.
    max_df = max(2, len(entries) // 4)
    df = {k: sum(1 for e in entries if k in e[2]) for k in keywords}
    ranked = []
    for header_line, title_words, body_words, instincts_file, line in entries:
        score = sum(2 if k in title_words else 1 for k in keywords
                    if k in body_words and df[k] <= max_df)
        if score >= 2:
            ranked.append((score, header_line, instincts_file, line))
    for score, header_line, path, line in sorted(ranked, key=lambda r: -r[0]):
        if header_line not in dossier["matched_instincts"]:
            dossier["matched_instincts"].append(header_line)
            dossier.setdefault("matched_instinct_refs", []).append(
                {"title": header_line, "file": path, "line": line, "score": score})

    # Không khớp gì thì để trống — không bịa danh sách mặc định.
    if not dossier["matched_instincts"]:
        dossier["matched_instincts_note"] = "Không có instinct nào khớp từ khoá của prompt."

    # 4. Generate Codebase Graph Search Queries
    tokens = [w for w in re.findall(r"[A-Za-z0-9_]{3,}", prompt) if w.lower() not in ["sửa", "lỗi", "giúp", "tạo", "làm", "cho", "vào", "khi", "bị"]]
    if tokens:
        dossier["codebase_queries"] = [
            f"search_graph(name_pattern=\".*{t}.*\")" for t in tokens[:3]
        ] + [
            "trace_path(function_name=\"<MatchedSymbol>\", direction=\"inbound\")"
        ]
    else:
        dossier["codebase_queries"] = [
            "search_graph(name_pattern=\".*<ComponentName>.*\")",
            "trace_path(function_name=\"<TargetFunction>\", direction=\"inbound\")"
        ]

    # Deduplicate recommended skills
    dossier["recommended_skills"] = list(dict.fromkeys(dossier["recommended_skills"]))

    return dossier

GENERIC_NFRS = 3  # the last three injected_nfrs apply to every task (already in the rules)


def compact(dossier, project_root, limit=4):
    """A few lines for the UserPromptSubmit hook — empty when the request matched no
    intent and no instinct (questions, chit-chat): no context tax on those."""
    intents = [i for i in dossier["detected_intents"] if i != "GENERAL_TASK"]
    refs = dossier.get("matched_instinct_refs", [])[:limit]
    if not intents and not refs:
        return ""
    out = [f"[DevKit] Ngữ cảnh tự động cho yêu cầu này (profile: {dossier['active_profile']}):"]
    if intents:
        out.append("- Loại việc: " + ", ".join(intents))
    if dossier.get("paired_oracle_spec", {}).get("required"):
        out.append("- Bắt buộc: chạy test tái hiện lỗi thấy ĐỎ trước khi sửa, XANH sau khi sửa "
                   "(Stop hook chỉ chấp nhận 'đã fix' khi thấy cặp RED→GREEN này).")
    specific = dossier["injected_nfrs"][:-GENERIC_NFRS]
    if specific:
        out.append("- Yêu cầu ngầm định: " + " · ".join(specific))
    for r in refs:
        rel = r["file"]
        if project_root and os.path.realpath(rel).startswith(os.path.realpath(project_root) + os.sep):
            rel = os.path.relpath(os.path.realpath(rel), os.path.realpath(project_root))
        out.append(f"- Bẫy đã gặp: {r['title']} — xem `sed -n '{r['line']},{r['line'] + 12}p' {rel}`")
    skills = [s for s in dossier["recommended_skills"] if s != "incremental-implementation" or intents]
    if skills:
        out.append("- Skill phù hợp: " + ", ".join(skills[:5]))
    return "\n".join(out)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--compact"]
    prompt_input = " ".join(args) if args else "sửa nút login bị bấm nhiều lần văng app"
    devkit_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or find_project_root(".")
    res = enrich_prompt(prompt_input, devkit_dir, project_dir)
    if "--compact" in sys.argv[1:]:
        text = compact(res, project_dir)
        if text:
            print(text)
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))
