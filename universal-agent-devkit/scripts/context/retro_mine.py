#!/usr/bin/env python3
"""retro_mine.py — read-only miner over agent transcripts (Claude Code + Antigravity).

Writes a compact JSONL corpus of:
  correction  : a human message that corrects / repeats / stops the agent (+ the agent turn before it)
  tool_error  : a tool result flagged as error (normalized signature, counted)
  hook_block  : a tool result where a devkit hook blocked the action
Never modifies the sources. Stdlib only.
Usage: retro_mine.py --out DIR [--claude ~/.claude/projects] [--agy ~/.gemini/antigravity/brain]
"""
import argparse, collections, glob, json, os, re, sys

CORR = re.compile(r"(?i)(\bsai\b|không phải|ko phải|k phải|đã bảo|đã nói|nói rồi|bảo rồi|sao lại|tại sao lại|lại nữa|vẫn (còn |chưa |bị |không )|chưa (đúng|xong|chạy|fix|sửa)|làm lại|đừng|không được|ko được|dừng|stop|revert|hoàn tác|bịa|fake|nói dối|chưa test|không test|đâu có|nhầm|quên|lặp lại|lần thứ|\bwrong\b|don't|do not|not what i|i said|i told you|again|still (broken|fail|not)|you forgot|why did you|undo|hallucinat)")
SKIP = re.compile(r"^\s*(<command-|<local-command|<system-reminder|Caveat:|\[Request interrupted)")
NUM = re.compile(r"0x[0-9a-f]+|\b\d+\b|/[\w./-]+|[0-9a-f]{8,}")

def text_of(content):
    if isinstance(content, str): return content
    out = []
    for p in content or []:
        if isinstance(p, dict) and p.get("type") == "text": out.append(p.get("text", ""))
    return "\n".join(out)

def trim(s, n): s = re.sub(r"\s+", " ", s or "").strip(); return s[:n]

def sig(s): return trim(NUM.sub("#", s), 160)

def mine_claude(root, w, errs, blocks, stats):
    for f in glob.glob(os.path.join(root, "*", "*.jsonl")):
        proj = os.path.basename(os.path.dirname(f)); sess = os.path.basename(f)[:-6]
        last_asst = ""; first_user = True; auto = False
        try: fh = open(f, encoding="utf-8", errors="replace")
        except OSError: continue
        stats["claude_files"] += 1
        for line in fh:
            try: d = json.loads(line)
            except ValueError: continue
            t = d.get("type"); m = d.get("message") or {}
            if t == "assistant":
                tx = text_of(m.get("content"))
                if tx: last_asst = tx
                for p in m.get("content") or []:
                    if isinstance(p, dict) and p.get("type") == "tool_use":
                        last_asst = (last_asst + f"\n[tool {p.get('name')}: {trim(json.dumps(p.get('input'), ensure_ascii=False), 200)}]")[-1500:]
            elif t == "user" and not d.get("isMeta"):
                c = m.get("content")
                if isinstance(c, list):
                    for p in c:
                        if isinstance(p, dict) and p.get("type") == "tool_result":
                            r = p.get("content"); r = r if isinstance(r, str) else text_of(r)
                            if re.search(r"(?i)hook.*(block|denied|refus)|PreToolUse.*(block|deny)|BLOCKED", r or ""):
                                blocks[sig(r)] += 1
                            elif p.get("is_error"):
                                errs[sig(r)] += 1
                tx = text_of(c)
                if not tx or SKIP.match(tx): continue
                stats["claude_user_msgs"] += 1
                if first_user:
                    first_user = False
                    auto = bool(re.search(r"(?i)super-board|You are a (build|qa|review)|worker", tx[:400]))
                    continue
                if auto: continue
                if CORR.search(tx):
                    w.write(json.dumps({"kind":"correction","src":"claude","project":proj,"session":sess,"ts":d.get("timestamp"),
                        "user":trim(tx,700),"agent_before":trim(last_asst,600)}, ensure_ascii=False)+"\n"); stats["corrections"] += 1

def mine_agy(root, w, errs, blocks, stats):
    for f in glob.glob(os.path.join(root, "*", ".system_generated", "logs", "transcript.jsonl")):
        sess = f.split(os.sep)[-4]; last_asst = ""; first = True
        stats["agy_files"] += 1
        for line in open(f, encoding="utf-8", errors="replace"):
            try: d = json.loads(line)
            except ValueError: continue
            src = str(d.get("source","")); typ = str(d.get("type","")); tx = d.get("content") or ""
            if not isinstance(tx, str): tx = json.dumps(tx, ensure_ascii=False)
            if src.upper().startswith("USER") or typ.upper() == "USER_INPUT":
                stats["agy_user_msgs"] += 1
                if first: first = False; continue
                if CORR.search(tx):
                    w.write(json.dumps({"kind":"correction","src":"antigravity","project":"","session":sess,"ts":d.get("created_at"),
                        "user":trim(tx,700),"agent_before":trim(last_asst,600)}, ensure_ascii=False)+"\n"); stats["corrections"] += 1
            elif src.upper() in ("MODEL","ASSISTANT","AGENT") or "PLANNER" in typ.upper():
                last_asst = tx[-1500:]
            if str(d.get("status","")).upper() in ("ERROR","FAILED"): errs[sig(tx)] += 1

def main():
    a = argparse.ArgumentParser()
    a.add_argument("--out", required=True)
    a.add_argument("--claude", default=os.path.expanduser("~/.claude/projects"))
    a.add_argument("--agy", default=os.path.expanduser("~/.gemini/antigravity/brain"))
    o = a.parse_args(); os.makedirs(o.out, exist_ok=True)
    errs, blocks, stats = collections.Counter(), collections.Counter(), collections.Counter()
    with open(os.path.join(o.out, "corrections.jsonl"), "w", encoding="utf-8") as w:
        mine_claude(o.claude, w, errs, blocks, stats)
        if os.path.isdir(o.agy): mine_agy(o.agy, w, errs, blocks, stats)
    json.dump({"stats":stats, "tool_errors":errs.most_common(300), "hook_blocks":blocks.most_common(150)},
              open(os.path.join(o.out, "signals.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps(stats))
if __name__ == "__main__": main()
