#!/usr/bin/env python3
# enrich_context.py — Autonomous Prompt Context & Intent Enrichment Engine
# Transforms a brief user prompt into a 5-dimensional technical specification dossier.

import sys
import os
import json
import re
import subprocess
import unicodedata

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


# "xoá" and "xóa", "hoà" and "hòa", "thuý" and "thúy": both tone placements are in use.
# Prompts and entries are matched in one form (the tone on the first vowel).
_TONE_SWAP = {"oá": "óa", "oà": "òa", "oả": "ỏa", "oã": "õa", "oạ": "ọa",
              "oé": "óe", "oè": "òe", "oẻ": "ỏe", "oẽ": "õe", "oẹ": "ọe",
              "uý": "úy", "uỳ": "ùy", "uỷ": "ủy", "uỹ": "ũy", "uỵ": "ụy"}
_TONE_RE = re.compile("(?:" + "|".join(_TONE_SWAP) + r")(?!\w)")


def normalize(text):
    """Lower case, NFC, one Vietnamese tone placement."""
    text = unicodedata.normalize("NFC", text).lower()
    return _TONE_RE.sub(lambda m: _TONE_SWAP[m.group(0)], text)


def word_set(text):
    """The words of text, plus the parts of each identifier: DocxEditor → docx, editor;
    applyUntrustedXmlSecurity → xml…; reader_error_docx → docx. An entry that names
    `SAXReader.applyUntrustedXmlSecurity` is about XML even if it never says "XML"."""
    out = set()
    for raw in re.findall(r"[\w$]+", unicodedata.normalize("NFC", text)):
        out.add(normalize(raw))
        if raw.isascii() and ("_" in raw or re.search(r"[a-z][A-Z]|[A-Z][A-Z][a-z]", raw)):
            out.update(w.lower() for w in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+", raw) if len(w) >= 3)
    return out


def mentions(text, keywords):
    """text (normalized) names one of keywords as a word or the start of one ("crash"
    finds "crashed"). A keyword of three characters or fewer must be a whole word
    (plural s allowed): "pr" is not in "PlayerPrefs", "ui" not in "build"."""
    for k in keywords:
        k = normalize(k)
        if re.search(r"(?<!\w)" + re.escape(k) + (r"s?(?!\w)" if len(k) <= 3 else ""), text):
            return True
    return False


# A defect report names what went wrong, not the word "bug": "bị xóa", "bị mất",
# "không chạy", "hiển thị sai". "bị" + verb is the adversative passive — something
# happened to the user — except in compounds (thiết bị, chuẩn bị, bị động) and when it
# is what the change should prevent ("không bị", "tránh bị").
DEFECT_RE = re.compile(
    r"(?<!thiết )(?<!chuẩn )(?<!trang )(?<!dự )(?<!phòng )(?<!không )(?<!tránh )(?<!khỏi )"
    r"(?<!\w)bị(?!\w)(?! động)"
    r"|(?<!\w)(?:không|chẳng) (?:chạy|hoạt động|hiện|hiển thị|lên|mở|lưu|nhận|vào|load|tải|phản hồi|"
    r"kết nối|phát|nghe|đóng|tắt|bật)(?!\w)"
    r"|(?<!\w)(?:sai|kẹt|mất dữ liệu|mất sạch|hồi quy|broken|wrong|regression)(?!\w)"
    r"|not working|doesn'?t work|does not work")
# Deprecation is a deliberate act — "xoá API cũ", "deprecate", "migrate sang" — not any
# sentence with "xóa" in it ("PlayerPrefs bị xóa" is a defect report).
DEPRECATION_RE = re.compile(
    r"(?<!\w)(?:deprecat|sunset|migrat|chuyển sang|di trú|ngừng hỗ trợ|khai tử)"
    r"|(?<!bị )(?<!\w)(?:xóa|bỏ|gỡ)(?:\s+\S+){0,3}?\s+(?:cũ|legacy|deprecated|obsolete)(?!\w)")

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
STOPWORDS = {normalize(w) for w in STOPWORDS}

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

    p_lower = normalize(prompt)

    # 2. Detect Intents & Recommend Skills
    if mentions(p_lower, ["lỗi", "bug", "crash", "văng", "hỏng", "fail", "sửa", "chết", "die"]) \
            or DEFECT_RE.search(p_lower):
        dossier["detected_intents"].append("BUG_FIX")
        dossier["recommended_skills"].extend(["fixbugs", "tdd-workflow", "verification-before-completion"])
        dossier["paired_oracle_spec"] = {
            "required": True,
            "rule": "PAIRED EXECUTABLE ORACLE: Must observe test RED before editing code, then GREEN after.",
            "compile_only_permitted_if": "The root defect itself is a compilation/build failure."
        }

    if mentions(p_lower, ["nút", "click", "bấm", "giao diện", "ui", "màn hình", "layout", "button", "tap"]):
        dossier["detected_intents"].append("UI_INTERACTION")
        dossier["injected_nfrs"].append("Debounce >= 1000ms + Instant Disable on 1st click + Loading indicator.")
        dossier["injected_nfrs"].append("Touch Target >= 48dp (Mobile) / >= 44px (Web).")
        dossier["injected_nfrs"].append("Design Tokens adherence: Semantic colors from DESIGN.md.")
        if dossier["active_profile"] == "android":
            dossier["recommended_skills"].append("android-real-device-qa")

    if mentions(p_lower, ["lag", "chậm", "đơ", "anr", "tối ưu", "hiệu năng", "fps", "treo", "freeze", "xoay",
                                   "giật", "jank", "stutter", "recompos", "leak", "rò rỉ", "retain cycle",
                                   "memory", "bộ nhớ", "oom"]):
        dossier["detected_intents"].append("PERFORMANCE_AND_RESPONSIVENESS")
        dossier["injected_nfrs"].append("Non-blocking Main Thread: Move heavy work/IO to background dispatchers.")
        dossier["injected_nfrs"].append("Algorithm complexity: O(1) lookup via Map/Set; avoid O(N^2) dynamic loops.")
        dossier["injected_nfrs"].append("Zero memory leaks: unregister listeners/observers upon lifecycle destroy.")
        dossier["recommended_skills"].append("observability-instrumentation")
        if dossier["active_profile"] == "android":
            dossier["recommended_skills"].append("android-real-device-qa")

    if mentions(p_lower, ["mạng", "api", "gọi", "request", "server", "timeout", "offline", "sync"]):
        dossier["detected_intents"].append("NETWORK_AND_RESILIENCE")
        dossier["injected_nfrs"].append("Explicit Timeouts: Connect <= 10s, Read <= 15s.")
        dossier["injected_nfrs"].append("Idempotency-Key (UUIDv4) for state-mutating requests (POST/PUT).")
        dossier["injected_nfrs"].append("Exponential backoff with jitter for retries.")

    if mentions(p_lower, ["xss", "csrf", "ssrf", "injection", "lỗ hổng", "bảo mật", "security", "rce",
                                   "auth bypass", "leo quyền", "privilege", "lộ token", "lộ secret", "cors"]):
        dossier["detected_intents"].append("SECURITY")
        dossier["recommended_skills"].append("security-checklist")
        dossier["injected_nfrs"].append("Validate & encode all untrusted input; parameterized queries only (no string-built SQL).")
        dossier["injected_nfrs"].append("Least privilege for tokens/roles; secrets from env/secret store, never logged.")

    if mentions(p_lower, ["refactor", "thiết kế", "kiến trúc", "module", "tách", "interface"]):
        dossier["detected_intents"].append("ARCHITECTURE_REFACTOR")
        dossier["recommended_skills"].extend(["grill-plan", "deep-module-design", "documentation-and-adrs", "incremental-implementation"])

    if DEPRECATION_RE.search(p_lower):
        dossier["detected_intents"].append("DEPRECATION_MIGRATION")
        dossier["recommended_skills"].extend(["deprecation-migration", "documentation-and-adrs"])

    if mentions(p_lower, ["giao cho", "giao việc", "giao task", "antigravity", "pm", "phân công"]):
        dossier["detected_intents"].append("DUAL_AGENT_DELEGATION")
        dossier["recommended_skills"].append("giao")

    if mentions(p_lower, ["crashlytics", "traces.txt", "stacktrace", "sập app", "triage"]):
        dossier["detected_intents"].append("CRASH_TRIAGE")
        dossier["recommended_skills"].append("fixbugs")

    if mentions(p_lower, ["conflict", "xung đột", "merge", "rebase", "cherry-pick"]):
        dossier["detected_intents"].append("MERGE_CONFLICT")
        dossier["recommended_skills"].append("merge-conflict-resolver")

    if mentions(p_lower, ["release", "deploy", "đóng gói", "apk", "aab", "publish", "phát hành",
                                   "testflight", "app store", "play store", "archive", "ipa", "submit"]):
        dossier["detected_intents"].append("RELEASE_DEPLOY")
        dossier["recommended_skills"].extend(["deploy", "qc", "verification-before-completion"])

    if mentions(p_lower, ["review", "pr", "pull request", "soát diff", "chất vấn", "nghiệm thu"]):
        dossier["detected_intents"].append("CODE_AND_QA_REVIEW")
        dossier["recommended_skills"].extend(["qa-review", "open-code-review", "verification-before-completion"])

    if mentions(p_lower, ["spec", "tính năng mới", "feature lớn", "yêu cầu mới"]):
        dossier["detected_intents"].append("SPEC_PLANNING")
        dossier["recommended_skills"].extend(["spec-driven-development", "grill-plan", "documentation-and-adrs"])

    if mentions(p_lower, ["vỡ layout", "tràn khung", "lệch giao diện", "screenshot", "chụp màn"]):
        dossier["detected_intents"].append("VISUAL_QA")
        dossier["recommended_skills"].append("qa-visual")

    if mentions(p_lower, ["tìm hàm", "ai gọi", "luồng gọi", "đồ thị", "graph"]):
        dossier["detected_intents"].append("CODEBASE_EXPLORE")
        dossier["recommended_skills"].append("codebase-memory")

    if mentions(p_lower, ["bàn giao", "checkpoint", "nén ngữ cảnh", "compact", "phiên dài"]):
        dossier["detected_intents"].append("SESSION_HANDOFF")
        dossier["recommended_skills"].append("session-handoff")

    if mentions(p_lower, ["viết skill", "tạo skill", "chuẩn hóa skill", "rule mới"]):
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
    # The prompt's own words only: splitting its identifiers too ("ViewModel" → viewmodel,
    # view, model) would let one name score three times. Entries ARE split (word_set), so
    # "docx" in a prompt still finds an entry that only says DocxEditor.
    keywords = {normalize(w) for w in re.findall(r"[\w$]+", unicodedata.normalize("NFC", prompt))
                if len(w) >= 3 and normalize(w) not in STOPWORDS}
    said = set(keywords)  # what the user wrote, before the intent's technical terms
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
            entries.append((header_line, word_set(header_line), word_set(full_block),
                            instincts_file, visible.count("\n", 0, m.start()) + 1,
                            " ".join(re.findall(r"[\w$]+", normalize(header_line))),
                            " ".join(re.findall(r"[\w$]+", normalize(full_block)))))
    # A word found in many entries (Vietnamese syllables like "cách", "động") says
    # nothing about WHICH trap applies: only words in at most a quarter of the
    # entries (min 2) score, and an entry needs 2+ points.
    # A lone Vietnamese syllable ("tổng", "quan", "kiến") is ambiguous on its own — it
    # scores half; two adjacent prompt words found together in the entry ("kiến trúc",
    # "thanh toán") score like a word. ASCII words (identifiers, tech terms) score full.
    # One Vietnamese word or phrase in common is not evidence when the request says more
    # and the entry shares none of it: in "cửa sổ xe bị kẹt" the window is a car window,
    # not the UI overlay window of an entry that only shares "cửa sổ". Such an entry is
    # kept only when that phrase is all the request says ("nhạc tắt sau 40 s").
    max_df = max(2, len(entries) // 4)
    df = {k: sum(1 for e in entries if k in e[2]) for k in keywords}
    words = [w for w in re.findall(r"[\w$]+", p_lower)]
    bigrams = {f"{a} {b}" for a, b in zip(words, words[1:])
               if a not in STOPWORDS and b not in STOPWORDS and (not a.isascii() or not b.isascii())}
    ranked = []
    for header_line, title_words, body_words, instincts_file, line, title_text, body_text in entries:
        phrases = [bg for bg in bigrams if bg in body_text]
        in_phrase = {w for bg in phrases for w in bg.split()}
        hits = [k for k in keywords if k in body_words and df[k] <= max_df]
        score = sum((2 if k in title_words else 1) * (1 if k.isascii() else 0.5) for k in hits)
        score += sum(2 if bg in title_text else 1 for bg in phrases)
        if (not any(k.isascii() for k in hits)
                and len(phrases) + len([k for k in hits if k not in in_phrase]) < 2
                and any(df[k] <= max_df for k in said - set(hits) - in_phrase)):
            continue
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
    refs = dossier.get("matched_instinct_refs", [])
    if not intents:
        # No kind of work detected (chit-chat, a general question): two stray word hits
        # are noise — only a strong match (3+ points, e.g. a title hit) is worth context.
        refs = [r for r in refs if r["score"] >= 3]
    refs = refs[:limit]
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


def hook_prompt(raw):
    """The prompt of a UserPromptSubmit payload, or "" when nothing should be added:
    slash commands, empty or very short prompts, unreadable input."""
    try:
        prompt = json.loads(raw).get("prompt") or ""
    except Exception:
        return ""
    if not isinstance(prompt, str) or prompt.startswith("/") or len(prompt) < 8:
        return ""
    return prompt


if __name__ == "__main__":
    if "--hook" in sys.argv[1:]:
        # hooks/prompt_context.sh: the hook payload on stdin, one process for all of it.
        prompt_input = hook_prompt(sys.stdin.read())
        if not prompt_input:
            sys.exit(0)
        sys.argv.append("--compact")
        args = [prompt_input]
    else:
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
