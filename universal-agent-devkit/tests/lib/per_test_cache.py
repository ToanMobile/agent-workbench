#!/usr/bin/env python3
"""per_test_cache.py — sổ PASS theo TỪNG test của run_impacted.sh (audit DevKit 25/10, mục B2).

Một TIMEOUT của REG-DK-ALL-01 (run_impacted.sh, trần 900 s của gate) vô hiệu mọi PASS bên trong nó: lượt sau chạy lại cả tập, lại quá giờ
(54 TIMEOUT = 14,3 h trong 54 h đo ở workbench). Nay mỗi test PASS được ghi NGAY khi nó xong, vào kho của bin/suite_cache.py theo khoá CẢ
CÂY của lệnh `bash <test>` (SuiteCache.keys()[1]: nội dung mọi file + đường dẫn test + môi trường + đích ngoài cây); lượt sau trên đúng cây đó
bỏ qua test đã PASS (sau TIMEOUT, worktree anh em cùng cây, merge gate cùng cây). Không khoá theo bao đóng tĩnh: nó bỏ sót "$D/lib/x" ở kit
lồng và `import` trong heredoc python của file .sh (review 26/10, F1).
04/11 ("lỗi 1 chỗ thì chạy lại 1 chỗ"): lượt không --all (runner đặt DEVKIT_PTC_INPUT_KEY=1) khoá test thường theo INPUT RIÊNG của nó —
SuiteCache.selection_inputs(runner, [test]), cùng đồ thị bin/scoped_gate.py mà khoá chính xác của shard đã tin (#851) — nên sửa một file chỉ
chạy lại test đọc nó. Test quét cả kit (devkit-selection-tree), test không phải nút đồ thị, runner không dấu, lượt --all: khoá cả cây. Một
lần chạy thật FAIL void mọi PASS cũ của test (mọi khoá).

  per_test_cache.py plan <kit> <out> <test>...   in "reuse<TAB><test><TAB><tuổi giây>" cho test dùng lại; test phải chạy thì ghi ảnh
                                                  khoá <out>/<test, "/"→"_">.ptc.json (+ dấu vân tay cây chung <out>/ptc.base.json)
  per_test_cache.py record <out> <test> <rc>     ghi kết quả của một lần chạy THẬT (rc của test)

Chỉ chạy khi gate bật (DEVKIT_PER_TEST_CACHE, post-fix-gate.py: "1" dùng lại + ghi theo khoá nội dung, "record" chỉ ghi — lượt sentinel /
--no-cache); `agent-kit test` của người dùng không đặt biến nên luôn chạy hết. Luật như suite (cùng mã SuiteCache, kho riêng
<kho suite>/per_test để không đẩy bản ghi suite ra khỏi STORE_MAX):
  - dùng lại ⇔ SuiteCache.hit: PASS trên đúng khoá (pass_n ≥ 1, fail_n = 0, không cách ly, không bị void) có lần chạy THẬT trong tuổi tối
    đa (DEVKIT_SUITE_CACHE_MAX_S / DEVKIT_GATE_CACHE_MAX_S, mặc định 6 h) — test được dùng lại phải chạy thật ít nhất một lần mỗi 6 h;
  - record ghi PASS khi cả cây (và đích ngoài cây) y nguyên sau khi test chạy VÀ không file nào của chúng bị ghi từ lúc plan (dấu stat
    ino, size, mtime_ns, ctime_ns lấy lúc plan, trước mọi test: sửa rồi hoàn tác A→B→A cùng bytes, kể cả trả lại mtime, vẫn đổi ctime —
    băm nội dung thì không thấy; #427); ghi FAIL lên khoá (SuiteCache.hit đòi fail_n = 0) và, khi
    khoá đang có PASS, gọi SuiteCache.contradiction (cùng cây mà khác kết quả: cách ly); PASS trên khoá có fail_n > 0 (cùng nội dung, chập
    chờn): cách ly id (QUARANTINE_S); TIMEOUT (124 của run_bounded) ghi timeout_n và void id; rc ≥ 128 (tín hiệu: crash của chính test,
    hay gate giết cả nhóm khi REG-DK-ALL-01 quá giờ) hay 64 (lỗi dùng run_bounded): không ghi kết quả, void id (review 26/10, F2).
  - plan không ghi ảnh khoá cho test có lệnh mạng (suite_cache.NETWORK): test đó chạy mỗi lượt.
Lỗi của helper (ngoại lệ, kho không đọc được) làm plan không in "reuse": test chạy.
"""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ID_PREFIX = "per-test:"


def _bin(kit):
    return os.path.join(kit, "bin")


def _suite_cache(kit):
    sys.path.insert(0, _bin(kit))
    import suite_cache  # noqa: PLC0415 - bin/ của kit vừa vào sys.path
    return suite_cache


def _snap_path(out, test):
    return os.path.join(out, test.replace("/", "_") + ".ptc.json")


def _project(kit):
    r = subprocess.run(["git", "-C", kit, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=30)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def _head(project):
    r = subprocess.run(["git", "-C", project, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=30)
    return r.stdout.strip() if r.returncode == 0 else None


def _stat_sig(path, follow=False):
    """"ino:size:mtime_ns:ctime_ns" của path ("-" khi không stat được). ctime đổi mỗi lần file bị ghi và người dùng không đặt lại được."""
    try:
        st = os.stat(path) if follow else os.lstat(path)
    except OSError:
        return "-"
    return f"{st.st_ino}:{st.st_size}:{st.st_mtime_ns}:{st.st_ctime_ns}"


def _stat_digest(project, rels):
    """sha256 của dấu stat mọi file của cây (lstat: symlink là chính nó) — record so với dấu lúc plan để bắt ABA (#427)."""
    h = hashlib.sha256()
    for rel in sorted(rels):
        h.update(os.fsencode(rel) + b"\0" + _stat_sig(os.path.join(project, rel)).encode() + b"\0")
    return h.hexdigest()


def _ext_sig(mod, project, tok):
    hit = mod._external(project, tok, "")
    return _stat_sig(hit[1], follow=True) if hit else "-"


def _input_key(mod, sc, runner, test, entry):
    """(khoá, (input, đích ngoài cây)) theo INPUT RIÊNG của test: SuiteCache.selection_inputs(runner, [test]) — cùng đồ thị
    bin/scoped_gate.py và cùng ranh giới tin với khoá chính xác của shard run_impacted.sh (#851; hợp input từng test = input của shard) —
    cộng input học được của id, đích ngoài cây mà các file đó nhắc, công cụ của chúng. (None, None) khi không tính được (không phải nút đồ
    thị, đồ thị lỗi, một input không đọc được): người gọi lùi về khoá cả cây."""
    files = sc.selection_inputs(runner, [test])
    if files is None:
        return None, None
    files = set(files)
    for pat in sc.learned.get(entry["id"]) or []:   # đường dẫn học được (contradiction) là đường dẫn thật, không phải glob
        files |= {pat} if pat in sc.cmap else sc.idx.glob(pat)
    ext, tools = {}, set()
    for p in sorted(files):
        if os.path.splitext(p)[1] not in mod._SCAN_EXT:
            continue
        full = os.path.join(sc.project_dir, p)
        info = mod._file_refs(sc.project_dir, sc.idx, full, p, os.path.dirname(p))
        if info is None:
            if os.path.isfile(full):   # như closure(): không đọc được thì không biết nó nguồn gì
                return None, None
            continue
        tools |= info[2]
        for tok, real in info[1]:
            ext.setdefault(tok, mod._file_digest(real))
    env_sel = sc.selection_env
    if isinstance(env_sel, dict):   # M1 của khoá shard: danh sách scoped gộp không phải input của một test (runner gỡ trước khi chạy)
        env_sel = {k: v for k, v in env_sel.items() if k != "DEVKIT_SCOPED_TESTS"}
    head = {"fmt": mod.SUITE_CACHE_FORMAT, "ptc": 1, "rf": sc.result_format, "id": entry["id"], "command": entry["command"],
            "runner": runner, "local": sc.local_sha, "sel": env_sel, "danger": sc.danger_digest,
            "env": mod.env_fingerprint(tools | mod._tools_in(entry["command"]))}
    h = hashlib.sha256(b"per-test-inputs\0" + json.dumps(head, sort_keys=True, default=str).encode())
    for p in sorted(files):
        h.update(b"f\0" + os.fsencode(p) + b"\0" + (sc.cmap.get(p) or "-").encode() + b"\0")
    for tok in sorted(ext):
        h.update(b"x\0" + os.fsencode(tok) + b"\0" + ext[tok].encode() + b"\0")
    return h.hexdigest(), (sorted(files), ext)


def plan(kit, out, tests):
    mode = os.environ.get("DEVKIT_PER_TEST_CACHE", "")
    if mode not in ("1", "record"):
        return 0
    kit = os.path.realpath(kit)
    project = _project(kit)
    if not project:
        return 0
    spec = importlib.util.spec_from_file_location("post_fix_gate_for_per_test", os.path.join(_bin(kit), "post-fix-gate.py"))
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    mod = gate.suite_cache_mod()
    sc = gate.suite_cache_for(project, [], None, {})   # None khi DEVKIT_SUITE_CACHE=0 hay kho hỏng: mọi test chạy, không ghi gì
    if mod is None or sc is None:
        return 0
    sc.store = os.path.join(sc.store, "per_test")
    sc.learned = sc.load_learned()   # input học được của kho per_test, không của kho suite
    # Ảnh lúc tính khoá: một file chung (dấu vân tay cả cây + dấu stat cả cây) + mỗi test khoá và đích ngoài cây của nó; record so lại cả
    # hai sau khi test chạy. Dấu stat lấy SAU khi đọc nội dung: file bị ghi giữa hai lúc đó thì hoặc nội dung lúc record khác khoá, hoặc
    # (hoàn tác) stat lúc record khác dấu này — không lần nào ghi PASS.
    # ponytail: một dấu stat cho cả lượt, lấy lúc plan — một lần ghi bất kỳ file nào của cây (kể cả touch) trong lượt bỏ PASS của mọi
    # test xong sau đó, cả test bắt đầu khi file đã yên; nâng cấp (dấu stat lúc từng test bắt đầu, trong run_one của run_impacted.sh)
    # khi đo thấy tỉ lệ dùng lại tụt vì việc này.
    base = {"v": 3, "project": project, "store": sc.store, "head": _head(project), "tree": sc.tree_digest,
            "stat": _stat_digest(project, sc.cmap or {})}
    if not _write(os.path.join(out, "ptc.base.json"), base):
        return 0
    # Khoá theo input từng test chỉ khi runner báo lượt này không phải --all (DEVKIT_PTC_INPUT_KEY=1, đặt riêng cho lệnh plan) VÀ runner
    # khai hợp đồng SELECTION_INPUTS_MARK; test runner nêu ở devkit-selection-tree (quét cả kit lúc chạy) giữ khoá cả cây.
    runner = os.path.relpath(os.path.join(kit, "tests", "run_impacted.sh"), project)
    tree_tests = mod.selection_inputs_marked(project, "bash " + runner) if os.environ.get("DEVKIT_PTC_INPUT_KEY") == "1" else None
    now = time.time()
    for test in tests:
        full = os.path.realpath(os.path.join(kit, test))
        rel = os.path.relpath(full, project)
        if rel.startswith("..") or not os.path.isfile(full):
            continue
        entry = {"id": ID_PREFIX + rel, "command": "bash " + rel}
        if mod.NETWORK.search(mod._read_text(full) or ""):
            continue   # đọc mạng ngay trong test: khoá nội dung không nói gì về kết quả
        # Không khoá theo bao đóng tĩnh của suite_cache: nó bỏ sót "$D/lib/x" ở kit lồng và `import` trong heredoc python của file .sh
        # (review 26/10, F1). Khoá theo input (đồ thị scoped_gate: import cả trong heredoc, `source`, nhắc basename, file dữ liệu theo chuỗi
        # con) khi tính được; còn lại KHOÁ CẢ CÂY (nội dung mọi file + đường dẫn test + môi trường): PASS chỉ dùng lại trên đúng cây đó.
        key, inputs = (None, None) if tree_tests is None or test in tree_tests else _input_key(mod, sc, runner, test, entry)
        if key is None:
            key = sc.keys(entry)[1]
        if not key:
            continue
        rec = sc.hit(key, entry, now) if mode == "1" else None   # hit() đã giới hạn tuổi PASS (mặc định 6 h)
        if rec:
            print(f"reuse\t{test}\t{int(now - rec['last_pass_at'])}")
            continue
        ext = inputs[1] if inputs else sc.input_values[(entry["id"], entry["command"])][1]
        _write(_snap_path(out, test), {"id": entry["id"], "command": entry["command"], "key": key, "ext": ext,
                                       "ext_stat": {tok: _ext_sig(mod, project, tok) for tok in ext},
                                       "inputs": inputs[0] if inputs else None})
    return 0


def _write(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        return True
    except OSError as exc:
        print(f"per_test_cache: không ghi được {path}: {exc}", file=sys.stderr)
        return False


def record(out, test, rc):
    try:
        with open(_snap_path(out, test), encoding="utf-8") as f:
            snap = json.load(f)
        with open(os.path.join(out, "ptc.base.json"), encoding="utf-8") as f:
            base = json.load(f)
        project, store, tree = base["project"], base["store"], base["tree"]
        rc = int(rc)
    except (OSError, ValueError, KeyError, TypeError):
        return 0   # không có ảnh khoá (lượt không bật cache, test đọc mạng…) hay ảnh hỏng: không ghi gì
    finished = time.time()
    mod = _suite_cache(os.path.dirname(os.path.dirname(HERE)))
    sc = mod.SuiteCache(project, [], None, {}, "per-test-record", 0, {}, learned={})
    sc.store = store
    entry = {"id": snap["id"], "command": snap["command"]}
    if rc >= 128 or rc == 64:
        # tín hiệu (crash 139/134 của chính test, hay gate giết nhóm) / lỗi dùng run_bounded: không phải kết luận PASS/FAIL, nhưng PASS cũ của
        # test này không còn đáng tin (review 26/10, F2) — void: lượt sau chạy thật
        sc.void(entry["id"], finished)
        print(f"per_test_cache: {entry['id']}: rc {rc} (tín hiệu / helper) — PASS cũ của test này hết dùng lại")
        return 0
    status = "PASS" if rc == 0 else ("TIMEOUT" if rc == 124 else "FAIL")
    if status == "PASS":
        # nội dung y nguyên chưa đủ: sửa rồi hoàn tác trong lúc test chạy (ABA, #427) cho đúng content_map cũ — so cả dấu stat lúc plan
        # (thiếu dấu: không ghi PASS)
        same = sc.cmap is not None and mod.tree_digest(sc.cmap) == tree and _stat_digest(project, sc.cmap) == base.get("stat")
        ext_stat = snap.get("ext_stat") or {}
        for tok, dig in snap["ext"].items():
            hit = mod._external(project, tok, "")
            same = same and bool(hit) and mod._file_digest(hit[1]) == dig and _stat_sig(hit[1], follow=True) == ext_stat.get(tok)
        if not same:
            print(f"per_test_cache: cây đổi trong lúc {test} chạy (nội dung, hay file bị ghi rồi hoàn tác) — không ghi PASS")
            return 0
    # input của khoá đã dùng (contradiction học phần thiếu): input riêng của test, hay cả cây
    inputs = snap.get("inputs") if isinstance(snap.get("inputs"), list) else (sc.cmap or {})
    sc.input_values[(entry["id"], entry["command"])] = (dict.fromkeys(inputs), snap["ext"])
    prev = sc.record(snap["key"], entry, status, {"head": base.get("head")}, at=finished)
    if status == "TIMEOUT":
        sc.void(entry["id"], finished)
    elif status == "FAIL":
        msg = sc.contradiction(snap["key"], entry, prev, False)
        if msg:
            print(f"per_test_cache: {msg}")
        # một lần chạy thật FAIL: mọi PASS cũ của test (mọi khoá) hết dùng lại — khoá theo input của một lượt scoped không được dùng lại
        # PASS cũ khi test vừa đỏ trên chính nội dung đó dưới khoá khác (lượt --all, khoá cả cây)
        sc.void(entry["id"], finished)
    elif prev and isinstance(prev.get("fail_n"), int) and prev["fail_n"] > 0:
        sc.quarantine(entry["id"])   # cùng khoá (cùng nội dung) từng FAIL nay PASS: chập chờn — hit() trả None cho id này hết QUARANTINE_S
        print(f"per_test_cache: {entry['id']}: khoá từng đỏ nay xanh (chập chờn) — cách ly, lượt sau chạy thật")
    return 0


def main(argv):
    if len(argv) >= 3 and argv[0] == "plan":
        return plan(argv[1], argv[2], argv[3:])
    if len(argv) == 4 and argv[0] == "record":
        return record(argv[1], argv[2], argv[3])
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 64


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:   # noqa: BLE001 - mọi lỗi chỉ làm test chạy lại, không bao giờ là PASS; nói rõ lỗi gì
        print(f"per_test_cache: {exc!r}", file=sys.stderr)
        sys.exit(0)
