import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
STUDIO_HTML = os.path.join(os.path.dirname(HERE), "web", "studio.html")


class TestStudioUiStandards(unittest.TestCase):
    def test_studio_html_exists_and_is_self_contained(self):
        self.assertTrue(os.path.isfile(STUDIO_HTML), "web/studio.html must exist")
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # No Antigravity or external Tailwind CDN
        self.assertNotIn("gstatic.com/antigravity", html)
        self.assertNotIn("cdn.tailwindcss.com", html)
        # Must define self-contained Light + Dark semantic tokens & Telegram theme bridge
        self.assertIn(":root", html)
        self.assertIn('[data-theme="dark"]', html)
        self.assertIn("viewport-fit=cover", html)
        self.assertIn("safe-area-inset-bottom", html)
        self.assertIn("visualViewport", html)
        self.assertIn("prefers-reduced-motion", html)

    def test_studio_zero_inline_handlers_and_uses_native_dialog(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # Zero inline onclick/onchange attributes (prevents XSS & draft-wiping patterns)
        self.assertIsNone(re.search(r'\bon(?:click|change|input|submit)\s*=', html, re.I))
        # Must use native <dialog> for accessible modals
        self.assertIn("<dialog", html)
        self.assertIn("showModal", html)

    def test_studio_ergonomics_44px_targets_8px_gaps_16px_mobile_inputs(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        self.assertIn("min-height: 44px", html)
        self.assertIn("min-width: 44px", html)
        self.assertIn("font-size: 16px", html)
        # Must include auth headers & real CC-Switcher fields
        self.assertIn("X-AAF-Studio", html)
        self.assertIn("X-Telegram-Init-Data", html)
        self.assertIn("X-AAF-Session", html)
        self.assertIn("needsForce", html)
        self.assertIn("repoAssignments", html)
        self.assertIn("allowOAuthLogin", html)

    def test_studio_switch_uses_target_and_fixes_account_bugs(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # Bug fix: switch action must send `target` (server.py cc_switcher_args rejects `account`)
        self.assertNotIn('{ action: "switch", account:', html)
        self.assertIn('action: "switch", target:', html)
        # Bug fix: repo assignment must NOT fallback to boolean r.pinnedInFile as account id
        self.assertNotIn("|| r.pinnedInFile ||", html)
        # Bug fix: history must format from/to/reason cleanly, never JSON.stringify(h)
        self.assertNotIn("JSON.stringify(h)", html)

    def test_studio_accounts_parity_with_cc_switcher(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # Weekly (7-day) & 5-hour quota meters + reset countdown
        self.assertIn("Quota 5 giờ", html)
        self.assertIn("Quota 7 ngày", html)
        self.assertIn("weeklyRemainingPct", html)
        self.assertIn("weeklyResetFormatted", html)
        self.assertIn("weeklyResetAtMs", html)
        # 4 KPI cards & anti-ban cooldown controls
        self.assertIn("Chống ban", html)
        self.assertIn("Chi phí CC Switch", html)
        self.assertIn("Sức khỏe", html)
        self.assertIn('action: "cooldown"', html)
        # Provider separation (Claude vs Antigravity)
        self.assertIn("Tài khoản Claude", html)
        self.assertIn("Antigravity", html)
        self.assertIn("Chọn tay", html)
        # Repo <-> Account grouped summary, add/remove support
        self.assertIn("Repo ↔ Tài khoản", html)
        self.assertIn("repo_add", html)
        self.assertIn("repo_remove", html)

    def test_studio_kanban_board_and_structured_inspector(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        # Kanban board default view + List switcher + Repo filter + Cancelled toggle
        self.assertIn("kanban-board", html)
        self.assertIn("kanban-col", html)
        self.assertIn('data-view="kanban"', html)
        self.assertIn('data-view="list"', html)
        self.assertIn("repoFilter", html)
        self.assertIn("showCancelled", html)
        # Structured Spec JSON parsing (acceptance list) instead of raw JSON dump
        self.assertIn("parseSpec", html)
        self.assertIn("acceptance", html)

    def test_studio_has_six_column_github_workflow_kanban(self):
        with open(STUDIO_HTML, encoding="utf-8") as f:
            html = f.read()
        for col in ('key: "ready"', 'key: "building"', 'key: "qa"', 'key: "review"', 'key: "blocked"', 'key: "done"'):
            self.assertIn(col, html, f"Missing workflow Kanban column {col}")
        for label in ("Ready", "Building", "QA", "Review", "Blocked", "Done"):
            self.assertIn(label, html, f"Missing workflow label {label}")

    def test_agent_office_config_uses_auto_agent_factory_instead_of_agent_workbench(self):
        import json
        cfg_path = os.path.join(os.path.dirname(HERE), "config.json")
        with open(cfg_path, encoding="utf-8") as f:
            cfg = json.load(f)
        self.assertNotIn("agent-workbench", cfg.get("repos", []))
        self.assertIn("AutoAgentFactory", cfg.get("repos", []))
        self.assertEqual(cfg.get("repoPaths", {}).get("AutoAgentFactory"), "/Volumes/Data/Toan/AutoAgentFactory")


if __name__ == "__main__":
    unittest.main()
