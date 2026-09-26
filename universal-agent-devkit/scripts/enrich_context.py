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
    r"(?<!thiết )(?<!chuẩn )(?<!trang )(?<!dự )(?<!phòng )(?<!không )(?<!ko )(?<!tránh )(?<!khỏi )"
    r"(?<!\w)bị(?!\w)(?! động)"
    r"|(?<!\w)(?:không|chẳng) (?:chạy|hoạt động|hiện|hiển thị|lên|mở|lưu|nhận|vào|load|tải|phản hồi|"
    r"kết nối|phát|nghe|đóng|tắt|bật)(?!\w)"
    r"|(?<!\w)(?:sai|kẹt|treo|màn hình đen|đen màn hình|mất dữ liệu|mất sạch|hồi quy|broken|wrong|regression)(?!\w)"
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
    active_profile_file = next((p for p in (os.path.join(project_root or devkit_root, ".agents", "active-profile.json"),
                                            os.path.join(project_root or devkit_root, ".active-profile.json"),
                                            os.path.join(devkit_root, ".active-profile.json"))
                                if os.path.exists(p)), "")
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

    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import hardware_boundaries as _hb
        hits = _hb.match_text(_hb.load(project_root or ""), prompt)
    except Exception:
        hits = []
    for row in hits[:3]:
        dossier["injected_nfrs"].insert(-GENERIC_NFRS if len(dossier["injected_nfrs"]) >= GENERIC_NFRS else 0,
                                         _hb.warning(row))
    if hits:
        dossier["hardware_boundaries"] = [r.get("id") for r in hits[:3]]

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


def shown_refs(dossier, limit=4):
    """The trap entries the hook actually prints for this dossier (compact() and the
    recall log / scripts/memory_stats.py share this one rule)."""
    intents = [i for i in dossier["detected_intents"] if i != "GENERAL_TASK"]
    refs = dossier.get("matched_instinct_refs", [])
    if not intents:
        # No kind of work detected (chit-chat, a general question): two stray word hits
        # are noise — only a strong match (3+ points, e.g. a title hit) is worth context.
        refs = [r for r in refs if r["score"] >= 3]
    return refs[:limit]


INSTINCT_ID_RE = re.compile(r"\[(INSTINCT-[A-Za-z0-9_-]+)\]")


def log_surfaced(project_root, session, prompt, refs):
    """One line per handled prompt in .claude/audit-gate/surfaced.jsonl — the traps shown
    (none is a data point too: it is the denominator of the recall rate). The prompt's
    sha1, never its text. SURFACED_LOG=0 off."""
    if os.environ.get("SURFACED_LOG", "1") == "0" or not os.path.isdir(os.path.join(project_root, ".agents")):
        return
    import hashlib
    import time
    rows = []
    for r in refs:
        m = INSTINCT_ID_RE.search(r["title"])
        path = r["file"]
        if os.path.realpath(path).startswith(os.path.realpath(project_root) + os.sep):
            path = os.path.relpath(os.path.realpath(path), os.path.realpath(project_root))
        rows.append({"id": m.group(1) if m else r["title"][:60], "file": path, "line": r["line"]})
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "session": session,
           "prompt_sha1": hashlib.sha1(prompt.encode("utf-8")).hexdigest(),
           "instinct_ids": [r["id"] for r in rows], "instinct_refs": rows}
    try:
        d = os.path.join(project_root, ".claude", "audit-gate")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "surfaced.jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass


def compact(dossier, project_root, limit=4):
    """A few lines for the UserPromptSubmit hook — empty when the request matched no
    intent and no instinct (questions, chit-chat): no context tax on those."""
    intents = [i for i in dossier["detected_intents"] if i != "GENERAL_TASK"]
    refs = shown_refs(dossier, limit)
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
    """(prompt, session_id, payload) of a UserPromptSubmit payload; prompt is "" when
    nothing should be added: slash commands, empty or very short prompts, unreadable input."""
    try:
        payload = json.loads(raw)
        prompt = payload.get("prompt") or ""
        session = str(payload.get("session_id") or payload.get("sessionId") or "")
    except Exception:
        return "", "", {}
    if not isinstance(prompt, str) or prompt.startswith("/") or len(prompt) < 8:
        return "", session, payload
    return prompt, session, payload


# A bug report names a defect. "sửa" alone is also "edit" ("sửa README cho rõ"): BUG_FIX
# still injects the RED→GREEN rule for it, but no checklist row is written.
DEFECT_WORDS = ["lỗi", "bug", "crash", "văng", "hỏng", "fail", "chết", "die", "exception", "anr"]
TITLE_MAX = 120
# A task about bugs already KNOWN reports none (2026-09-25: "viết test cho các bug còn lại", "link
# bug luôn đi", "tổng số bugs", "docs/plan/…-5-bug.md", "/geely-fixbugs" became REPORTED rows).
# Before looking for a defect word, drop paths / slash commands / file names, and "bug(s)" as a
# counted set or the object of a task. A symptom in the same prompt still reports ("fix bug crash
# khi mở PDF": crash; "…vẫn chưa được, audit thêm bug": "thêm bug" is not a known set).
# A screenshot / video dropped in a bug(s)/ folder IS the evidence of a report ("…bugs/img.png",
# "(bugs/img.png)", a macOS "bugs/Screenshot … 10.23.45.png") — a signal of its own, checked
# before paths go. A path is a token that looks like one: starts with ~ . /, is a URL, has two
# slashes, or one slash with a digit/-/_ or a known extension, or name.<known extension>;
# "crash/văng", "fail/timeout" and "crash.Fix" (a missing space) are words (review 2026-09-26).
# Every branch is anchored at a token start: no quadratic scan of a long pasted token.
_EXT = (r"(?:md|txt|log|json|ya?ml|toml|xml|kts?|java|py|sh|tsx?|jsx?|gradle|pdf|docx?|xlsx?|pptx?|csv"
        r"|html?|css|swift|go|rs|patch|diff|zip|apk|aab|png|jpe?g|gif|webp|heic|mp4|mov|webm|mkv)")
PATHLIKE_RE = re.compile(
    r"(?<!\S)(?:[~./]\S*|\S*://\S*|[^\s/]*/[^\s/]*/\S*|[^\s/]*/[^\s/]*[-_\d][^\s/]*"
    r"|[^\s/]*/[^\s/]*\." + _EXT + r"|[^\s/]+\." + _EXT + r")(?![\w/])")
BUG_EVIDENCE_RE = re.compile(r"(?<![\w-])bugs?/[^\n]{0,200}?\.(?:png|jpe?g|gif|webp|heic|mp4|mov|webm|mkv)(?!\w)")
# The user says outright it is no report: "ko hỏi vấn đề của project đó bị gì", "20 dòng không
# phải bug" (2026-09-26; measured on 6158 real prompts: the only 2 user prompts it matches).
# Only that clause goes (to the next , . ; ! ? or line end): "app bị crash khi mở PDF, không phải
# lỗi mạng" still reports its crash (review 2026-09-26).
NOT_A_REPORT_RE = re.compile(r"(?<!\w)(?:không|ko|chẳng|chả)\s+(?:hỏi|phải|nói)\s+(?:về\s+)?(?:vấn đề|lỗi|bug|bị gì)[^,.;!?\n]*")
# Only the word bug(s) goes, the counting in front of it stays: "fix 2 crash bugs" keeps "crash".
KNOWN_BUGS_RE = re.compile(
    r"((?<!\w)(?:các|những|mấy|mọi|tất cả|all|\d+|tổng số|số lượng|số|link|gắn|viết test cho|test cho"
    r"|list|danh sách|checklist)\s+(?:\w+\s+)?)bugs?(?!\w)")

# Agent and harness prompts are not the user's bug reports. Grok (2026-09-25, OfficeReader)
# runs the prompt hook for its own sub-agents too, and "You are a hostile code reviewer. Do
# NOT edit any file…" / "You are the Goal Plan Writer for the xAI Grok Build harness" became
# REPORTED rows. Signals, each one enough on its own:
#   - a role assignment opening: "You are a/the <role>", "Act as a …", "Bạn là (một) <vai>", "Đóng vai …";
#   - a tool or JSON schema in the prompt (two distinct schema markers);
#   - a long instruction block: > 1500 characters with ≥ 6 directives (must / never / do
#     not / respond with / output format / markdown headings …). A pasted crash log is long
#     too, but it carries no directives, so length alone never drops a report.
# Only a role ASSIGNMENT counts: "You are a/an/the <role>", "Act as a …", "Your role is …",
# "As an AI/assistant …", "Bạn là (một) <vai>", "(Hãy) đóng vai …". A user's report that just
# starts with those words ("You are right, but it still crashes", "Bạn là dev Android thì xem
# giúp: app crash …", "Your task is to fix the crash") is still recorded (review 2026-09-25).
ROLE_OPENING = re.compile(
    r"^\W*((you are|you're|act as)\s+(a|an|the)\s+\w|your role is\b|as an? (ai|assistant|language model)\b|"
    r"(bạn là|mày là)\s+(một\s+)?(reviewer|agent|trợ lý|chuyên gia|kỹ sư|kiểm thử viên|planner|writer|auditor|"
    r"người (viết|đánh giá|kiểm|review))\b|(hãy\s+)?đóng vai\b)", re.I)
SCHEMA_MARKERS = [re.compile(p, re.I) for p in (
    r'"input_schema"\s*:', r'"\$schema"\s*:', r'"properties"\s*:\s*\{', r'"type"\s*:\s*"object"',
    r'"parameters"\s*:\s*\{', r'"required"\s*:\s*\[', r"<tool_call\b", r"<function_calls>", r"</invoke>",
    r"<functions>", r'"tool_choice"\s*:')]
DIRECTIVE = re.compile(r"\b(you must|you will|you should|must not|do not|don't|never|always|your (task|job|role|goal|output)|"
                       r"respond (only )?with|output format|return only|only output|không được|bắt buộc|cấm)\b", re.I)
HEADING = re.compile(r"^\s{0,3}#{1,4}\s+\S", re.M)


def harness_prompt(prompt, payload=None, env=None):
    """Why this prompt is an agent or harness prompt rather than a user's report, or "".
    Decided by the prompt's content only: the agent that runs the hook (Grok, Codex, Gemini,
    Cursor) says nothing — a user's bug report is recorded under every agent (2026-09-25)."""
    first = next((l.strip() for l in prompt.splitlines() if l.strip()), "")
    if ROLE_OPENING.match(first):
        return "role-play opening"
    if sum(1 for m in SCHEMA_MARKERS if m.search(prompt)) >= 2:
        return "tool/JSON schema"
    if len(prompt) > 1500 and len(DIRECTIVE.findall(prompt)) + len(HEADING.findall(prompt)) >= 6:
        return "instruction block"
    return ""


def capture_bug(prompt, dossier, project_root, session, payload=None):
    """A bug prompt → a REPORTED row in .agents/regression_status.json (deduplicated
    against rows still open), so a reported bug is on the checklist before anyone fixes
    it. Only in a project that already keeps a checklist or matrix; never raises.
    Not for agent / harness prompts (harness_prompt), nor for prompts under a non-Claude
    harness: Grok discards this hook's output, so the row would be written silently.
    Returns the context line to add, or ""."""
    if "BUG_FIX" not in dossier["detected_intents"] or os.environ.get("BUG_CAPTURE", "1") == "0":
        return ""
    if harness_prompt(prompt, payload):
        return ""
    agents = os.path.join(project_root, ".agents")
    if not (os.path.isfile(os.path.join(agents, "regression_status.json"))
            or os.path.isfile(os.path.join(agents, "regression_matrix.active.json"))):
        return ""
    first = next((l.strip() for l in prompt.splitlines() if l.strip()), "")
    # A wrapped message (<cross-session-message …>, <task-notification>) is not the user's report.
    if not first or first.startswith("<"):
        return ""
    p_norm = normalize(prompt)
    p_norm = NOT_A_REPORT_RE.sub(" ", p_norm)
    p_lower = KNOWN_BUGS_RE.sub(r"\1 ", PATHLIKE_RE.sub(" ", p_norm))
    if not (BUG_EVIDENCE_RE.search(p_norm) or mentions(p_lower, DEFECT_WORDS) or DEFECT_RE.search(p_lower)):
        return ""
    title = " ".join(first.split())
    if len(title) > TITLE_MAX:
        title = title[:TITLE_MAX - 1].rstrip() + "…"
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin"))
        sys.dont_write_bytecode = True     # no __pycache__ inside a linked DevKit
        import regression_checklist as rc
        with rc.locked(project_root):
            data = rc.load(project_root)
            before = json.dumps(data["items"].get(rc.find_bug(data, title, open_only=True) or ""), sort_keys=True)
            bid, created = rc.register_bug(data, title, state="reported", session=session or None, open_only=True)
            if created or json.dumps(data["items"][bid], sort_keys=True) != before:
                rc.save(project_root, data, stale=False)
            status = rc.effective_status(data, data["items"][bid])
    except Exception:  # noqa: BLE001 — a corrupt checklist must never break the prompt
        return ""
    return (f"- Bug đã ghi vào checklist: {bid} ({status}) — link test ĐỎ→XANH khi sửa xong: "
            f"`agent-kit bugs link {bid} <test>`; không phải bug: `agent-kit bugs drop {bid}`")


def _checklist_on(project_root):
    agents = os.path.join(project_root, ".agents")
    return (os.path.isfile(os.path.join(agents, "regression_status.json"))
            or os.path.isfile(os.path.join(agents, "regression_matrix.active.json")))


def watch_inbox(project_root):
    """New `- [ ]` lines of the user's .agents/INBOX.md → the context, once each. The file
    is only read — never written; what was seen is kept in regression_status.json."""
    if os.environ.get("INBOX_WATCH", "1") == "0" or not _checklist_on(project_root) \
            or not os.path.isfile(os.path.join(project_root, ".agents", "INBOX.md")):
        return ""
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin"))
        sys.dont_write_bytecode = True
        import regression_checklist as rc
        with rc.locked(project_root):
            data = rc.load(project_root)
            new = rc.inbox_new(data, project_root)
            if new:
                rc.save(project_root, data, stale=False)
    except Exception:  # noqa: BLE001 — the inbox must never break the prompt
        return ""
    if not new:
        return ""
    out = [f"- 📥 Hộp thư có {len(new)} mục mới (.agents/INBOX.md — chỉ đọc, KHÔNG sửa file này):"]
    for key, text, now in new[:10]:
        out.append(f"    • {text}  [key {key}]" + ("  → @làm: làm luôn (tiêu chí → test ĐỎ → code → XANH)" if now else ""))
    out.append("  Ghi thành REQ (tiêu chí trước khi code): "
               "`agent-kit req add \"<tiêu đề>\" --inbox <key> --criterion \"…\" --source \"<nguyên văn mục>\"`")
    return "\n".join(out)


SEVERITY_RANK = [("critical", 0), ("blocker", 0), ("p0", 0), ("high", 1), ("p1", 1), ("medium", 2), ("p2", 2),
                 ("low", 3), ("p3", 3)]
BACKLOG_LIMIT = 10


def _severity(sev):
    s = str(sev or "").lower()
    return next((r for k, r in SEVERITY_RANK if k in s), 4)


def command_words(prompt, project_root):
    """"làm backlog" / "làm inbox": the work list itself goes into the context, so one
    short prompt starts a whole batch."""
    p = normalize(prompt)
    want_backlog = re.search(r"(?<!\w)làm\s+backlog(?!\w)", p)
    want_inbox = re.search(r"(?<!\w)làm\s+(?:inbox|hộp thư)(?!\w)", p)
    if not (want_backlog or want_inbox) or not _checklist_on(project_root):
        return ""
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin"))
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        sys.dont_write_bytecode = True
        import regression_checklist as rc
        data = rc.load(project_root)
    except Exception:  # noqa: BLE001
        return ""
    out = []
    if want_backlog:
        rows = [(bid, it) for bid, it in data["items"].items() if it.get("kind") == "bug"
                and rc.effective_status(data, it) in ("NEEDS_TEST", "NOT_IN_MATRIX", "VACUOUS")]
        rows.sort(key=lambda r: (_severity(r[1].get("severity")), r[0]))
        proof = os.path.join(os.path.dirname(os.path.abspath(__file__)), "red_proof.py")
        try:
            from red_proof import fix_commit_of
        except Exception:  # noqa: BLE001
            fix_commit_of = lambda *_: (None, None)  # noqa: E731
        out.append(f"- 🧹 Làm backlog: {len(rows)} bug chưa có test hồi quy thật (xếp critical/P0 → P1 → P2 → chưa phân loại"
                   f", {min(len(rows), BACKLOG_LIMIT)} đầu). Mỗi bug: viết test tái hiện → `agent-kit bugs link <BUG> <test>` →"
                   " chạy gate → RED-proof (test phải ĐỎ trên code chưa sửa):")
        for bid, it in rows[:BACKLOG_LIMIT]:
            sha, why = fix_commit_of(__import__("pathlib").Path(project_root), it)
            how = (f"`python3 {proof} . --bug {bid} --fix-commit {sha} --wait`" if sha
                   else f"{why} — chọn đúng commit rồi --fix-commit, hoặc --patch <file đưa bug trở lại>" if why
                   else f"không có commit fix → viết patch đưa bug trở lại rồi `python3 {proof} . --bug {bid} --patch <file> --wait`")
            out.append(f"    • {bid} [{it.get('severity') or '-'}] {str(it.get('title', ''))[:80]} — {how}")
    if want_inbox:
        box = data.get("inbox") or {}
        todo = []
        for key, text, now in rc.read_inbox(project_root):
            req = (box.get(key) or {}).get("req")
            if req and req in data["items"] and rc.effective_status(data, data["items"][req]) == "PASS":
                continue
            todo.append((key, text, req))
        out.append(f"- 📥 Làm inbox: {len(todo)} mục chưa xong (.agents/INBOX.md — chỉ đọc). Mỗi mục: "
                   "`agent-kit req add \"<tiêu đề>\" --inbox <key> --criterion …` → test ĐỎ → code → XANH → `req link`:")
        for key, text, req in todo[:BACKLOG_LIMIT]:
            out.append(f"    • {text}  [key {key}]" + (f" → {req}" if req else ""))
    return "\n".join(out)


# "thêm tính năng …", "tạo màn hình …", "implement the … endpoint": new behaviour to specify.
FEATURE_RE = re.compile(
    r"(?<!\w)(?:thêm|tạo|làm|xây|viết|phát triển|bổ sung)\s+(?:mới\s+)?(?:tính năng|chức năng|màn hình|trang|nút|"
    r"api|endpoint|feature|luồng|báo cáo)|tính năng mới"
    r"|\b(?:add|implement|build|create)\s+(?:a |an |the |new )?(?:feature|screen|page|endpoint|button|flow|report)")


def req_hint(prompt, dossier, project_root):
    if "BUG_FIX" in dossier["detected_intents"] or not _checklist_on(project_root) \
            or not FEATURE_RE.search(normalize(prompt)):
        return ""
    return ("- Yêu cầu mới: ghi REQ + tiêu chí nghiệm thu kiểm được TRƯỚC khi code (khoá hash, sửa phải có --reason): "
            "`agent-kit req add \"<tiêu đề>\" --criterion \"…\" --source \"<nguyên văn prompt>\"`; "
            "review độc lập so tiêu chí với nguyên văn prompt; link test từng tiêu chí: `agent-kit req link <REQ> <n|all> <test>`")


if __name__ == "__main__":
    if "--hook" in sys.argv[1:]:
        # hooks/prompt_context.sh: the hook payload on stdin, one process for all of it.
        prompt_input, session_id, hook_payload = hook_prompt(sys.stdin.read())
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
        if "--hook" in sys.argv[1:]:
            log_surfaced(project_dir, session_id, prompt_input, shown_refs(res))
            extra = [l for l in (capture_bug(prompt_input, res, project_dir, session_id, hook_payload),
                                 req_hint(prompt_input, res, project_dir), watch_inbox(project_dir),
                                 command_words(prompt_input, project_dir)) if l]
            if extra:
                text = "\n".join(([text] if text else [f"[DevKit] Ngữ cảnh tự động (profile: {res['active_profile']}):"])
                                  + extra)
        if text:
            print(text)
    else:
        print(json.dumps(res, indent=2, ensure_ascii=False))
