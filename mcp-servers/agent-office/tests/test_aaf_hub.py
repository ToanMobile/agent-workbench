import json
import os
import sqlite3
import tempfile
import time
import unittest
from unittest import mock

import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import aaf_hub  # noqa: E402


def _create_sample_db(db_path: str, repo_root: str, wt_path: str, *, run_count: int = 2) -> None:
    con = sqlite3.connect(db_path)
    con.executescript(
        """
        CREATE TABLE accounts (
            id TEXT PRIMARY KEY,
            provider TEXT,
            config_dir TEXT,
            cooldown_until INTEGER,
            name TEXT
        );
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            repo_root TEXT,
            parent_id TEXT,
            root_id TEXT,
            depth INTEGER,
            title TEXT,
            spec TEXT,
            context_notes TEXT,
            state TEXT,
            priority TEXT,
            fingerprint TEXT,
            blocked_reason TEXT,
            unblock_cycles INTEGER,
            created_at INTEGER,
            updated_at INTEGER,
            scope_paths TEXT
        );
        CREATE TABLE runs (
            id TEXT PRIMARY KEY,
            task_id TEXT,
            account_id TEXT,
            executor TEXT,
            worktree_path TEXT,
            branch TEXT,
            status TEXT,
            exit_code INTEGER,
            tokens_in INTEGER,
            tokens_out INTEGER,
            started_at INTEGER,
            ended_at INTEGER
        );
        CREATE TABLE root_budgets (
            root_id TEXT PRIMARY KEY,
            tokens_used INTEGER,
            token_limit INTEGER,
            wall_secs_used INTEGER,
            wall_secs_limit INTEGER,
            cycles_used INTEGER,
            cycles_limit INTEGER,
            frozen INTEGER
        );
        CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT,
            run_id TEXT,
            kind TEXT,
            payload_json TEXT,
            created_at INTEGER
        );
        """
    )
    now = int(time.time())
    con.execute(
        "INSERT INTO accounts VALUES (?,?,?,?,?)",
        ("acc1", "claude_code", "~/.claude-finos", now + 3600, "finos_lua"),
    )
    con.execute(
        "INSERT INTO accounts VALUES (?,?,?,?,?)",
        ("acc2", "claude_code", "~/.claude-max", now - 300, "finos_toan_max"),
    )
    con.execute(
        "INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            "t-561",
            repo_root,
            None,
            "t-561",
            0,
            "Fix Android 15 delete",
            "Spec text",
            "",
            "blocked",
            "P0",
            "fp1",
            "head_lock: StoragePermissionTest.kt",
            0,
            now - 120,
            now - 10,
            '["feature/storage"]',
        ),
    )
    con.execute(
        "INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            "t-459",
            repo_root,
            None,
            "t-459",
            0,
            "Fix Bluetooth reconnect",
            "Spec bt",
            "",
            "review",
            "P1",
            "fp2",
            "",
            0,
            now - 240,
            now - 5,
            "[]",
        ),
    )
    for idx in range(run_count):
        rid = f"run_{idx:016x}"
        con.execute(
            "INSERT INTO runs VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                rid,
                "t-459" if idx == 0 else "t-561",
                "acc2",
                "claude_code",
                wt_path,
                "aaf/t-459",
                "running" if idx == 0 else "done",
                0,
                1000,
                500,
                now - 60,
                None if idx == 0 else now - 10,
            ),
        )
    con.commit()
    con.close()


class TestAafHub(unittest.TestCase):
    def test_redact_aaf_masks_telegram_bot_tokens(self):
        tok = "1234567890" + ":" + "AAH" + "1234567890abcdefGHIJKLMNOPQRSTUV"
        s = f"GET https://api.telegram.org/bot{tok}/getUpdates raw={tok}"
        out = aaf_hub.redact_aaf(s)
        self.assertNotIn("AAH1234567890", out)
        self.assertNotIn(tok, out)

    def test_read_studio_state_exact_counts_and_cooldown_expiry(self):
        with tempfile.TemporaryDirectory() as td:
            repo_root = os.path.join(td, "GeelyEx2")
            wt = os.path.join(td, "wt-1")
            os.makedirs(repo_root)
            os.makedirs(wt)
            db = os.path.join(td, "aaf.db")
            _create_sample_db(db, repo_root, wt, run_count=5)

            state = aaf_hub.read_studio_state(
                db_path=db,
                repo_paths={"GeelyEx2": repo_root},
                throttle_dir=os.path.join(td, "throttle"),
                include_manual=False,
            )
            self.assertTrue(state["ok"])
            self.assertEqual(state["summary"]["runsTotal"], 5)
            # Attention inbox must pin both blocked and review tasks
            att_ids = [t["id"] for t in state["attention"]]
            self.assertIn("t-561", att_ids)
            self.assertIn("t-459", att_ids)
            # Expired cooldown_until must NOT be marked active cooldown
            by_name = {a["name"]: a for a in state["aafAccounts"]}
            self.assertTrue(by_name["finos_lua"]["inCooldown"])
            self.assertFalse(by_name["finos_toan_max"]["inCooldown"])

    def test_read_studio_state_missing_db_graceful(self):
        with tempfile.TemporaryDirectory() as td:
            state = aaf_hub.read_studio_state(
                db_path=os.path.join(td, "missing.db"),
                repo_paths={"GeelyEx2": td},
                throttle_dir=os.path.join(td, "throttle"),
                include_manual=False,
            )
            self.assertTrue(state["ok"])
            self.assertEqual(state["tasks"], [])
            self.assertFalse(state["dbExists"])

    def test_stream_tail_blocks_symlink_and_path_traversal_and_redacts(self):
        with tempfile.TemporaryDirectory() as td:
            streams = os.path.join(td, "streams")
            os.makedirs(streams)
            secret_file = os.path.join(td, "secret.txt")
            with open(secret_file, "w", encoding="utf-8") as f:
                f.write("supersecret\n")
            sym = os.path.join(streams, "aaaa1111bbbb2222.jsonl")
            os.symlink(secret_file, sym)

            # Symlink must be refused via O_NOFOLLOW
            res_sym = aaf_hub.read_stream_tail("aaaa1111bbbb2222", streams_dir=streams)
            self.assertFalse(res_sym["ok"])

            # Traversal must be refused
            res_trav = aaf_hub.read_stream_tail("../secret", streams_dir=streams)
            self.assertFalse(res_trav["ok"])

            # Valid file must redact tokens
            good = os.path.join(streams, "deadbeef12345678.jsonl")
            tok = "987654321" + ":" + "AAH_" + "abcdefghijklmnopqrstuvwxyz12345"
            with open(good, "w", encoding="utf-8") as f:
                f.write(json.dumps({"kind": "tool", "title": f"curl {tok}"}) + "\n")
            res_ok = aaf_hub.read_stream_tail("deadbeef12345678", streams_dir=streams)
            self.assertTrue(res_ok["ok"])
            self.assertEqual(len(res_ok["events"]), 1)
            self.assertNotIn("AAH_abcdef", json.dumps(res_ok["events"]))

    def test_proof_png_validation_and_symlink_rejection(self):
        with tempfile.TemporaryDirectory() as td:
            repo_root = os.path.join(td, "OfficeReader")
            os.makedirs(repo_root)
            valid_png = os.path.join(repo_root, "proof.png")
            with open(valid_png, "wb") as f:
                f.write(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            fake_png = os.path.join(repo_root, "fake.png")
            with open(fake_png, "wb") as f:
                f.write(b"NOT_A_PNG")
            outside = os.path.join(td, "outside.png")
            with open(outside, "wb") as f:
                f.write(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            sym = os.path.join(repo_root, "sym.png")
            os.symlink(outside, sym)

            data, err = aaf_hub.read_proof_png(valid_png, allowed_roots=[repo_root])
            self.assertIsNone(err)
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))

            data2, err2 = aaf_hub.read_proof_png(fake_png, allowed_roots=[repo_root])
            self.assertIsNone(data2)
            self.assertIsNotNone(err2)

            data3, err3 = aaf_hub.read_proof_png(sym, allowed_roots=[repo_root])
            self.assertIsNone(data3)
            self.assertIsNotNone(err3)

    def test_clap_flag_injection_hardening(self):
        add_args = aaf_hub.build_board_add_args(
            title="-evil-title",
            spec="--danger-spec",
            accept="-check",
            priority="P1",
            scope="-path",
        )
        self.assertIn("--title=-evil-title", add_args)
        self.assertIn("--spec=--danger-spec", add_args)
        self.assertIn("--accept=-check", add_args)
        self.assertIn("--scope=-path", add_args)

        steer_args = aaf_hub.build_board_steer_args("t-123", "--force-ignore-all")
        sep_idx = steer_args.index("--")
        self.assertEqual(steer_args[sep_idx + 1 :], ["t-123", "--force-ignore-all"])

        rework_args = aaf_hub.build_board_rework_args("t-123", "-leading-dash reason", rerun=True)
        self.assertIn("--reason=-leading-dash reason", rework_args)
        self.assertIn("--", rework_args)

    def test_throttle_slots_ignores_empty_and_dead_lock_files(self):
        with tempfile.TemporaryDirectory() as td:
            # 0-byte leftover lock file must NOT count as held
            open(os.path.join(td, "heavy.0.lock"), "w", encoding="utf-8").close()
            # Dead pgid lock file must NOT count as held
            with open(os.path.join(td, "heavy.1.lock"), "w", encoding="utf-8") as f:
                f.write("pgid=99999999\n")
            # Active flock-held lock file MUST count as held
            import fcntl
            active_p = os.path.join(td, "heavy.2.lock")
            fd = os.open(active_p, os.O_CREAT | os.O_RDWR, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                os.write(fd, f"pgid={os.getpgrp()}\n".encode("ascii"))
                res = aaf_hub.read_throttle_slots(td, max_slots=3)
                self.assertEqual(res["held"], 1)
            finally:
                os.close(fd)

    def test_emergency_stop_pgid_safety(self):
        my_pid = os.getpid()
        my_pgid = os.getpgrp()
        # Never allow killing self or own PGID
        self.assertFalse(
            aaf_hub.can_killpg_safely(
                my_pgid,
                pgid_members=[(my_pid, "python3 server.py")],
                allowed_cmds=("claude", "aaf"),
            )
        )
        # Never allow killpg if unrelated zsh shell shares the PGID
        self.assertFalse(
            aaf_hub.can_killpg_safely(
                99999,
                pgid_members=[(99999, "claude -p task"), (99998, "/bin/zsh")],
                allowed_cmds=("claude", "aaf"),
            )
        )
        # Safe when all members in PGID are verified agent children
        self.assertTrue(
            aaf_hub.can_killpg_safely(
                88888,
                pgid_members=[(88888, "aaf run --auto"), (88889, "claude --print")],
                allowed_cmds=("claude", "aaf"),
            )
        )


if __name__ == "__main__":
    unittest.main()
