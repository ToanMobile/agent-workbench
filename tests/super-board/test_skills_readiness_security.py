#!/usr/bin/env python3
"""The QA lane requires pr-security-review and the Review lane does not (upstream 3.3.0, T0247)."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / '.claude/bin/super-board-skills-ready.py'
CORE = ['super-board', 'super-build', 'super-qa', 'super-review', 'super-collect', 'visual', 'git-sync',
        'ui-refine-loop', 'pr-security-review']
OTHER = ['tdd', 'implement', 'codebase-design', 'code-review', 'diagnosing-bugs',
         'verification-before-completion', 'testing-strategy']


class SecurityReadiness(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project'
        self.home = Path(self.temp.name) / 'home'
        self.root.mkdir()
        self.home.mkdir()
        for name in CORE + OTHER:
            self.put(name)

    def put(self, name):
        path = self.root / '.claude/skills' / name / 'SKILL.md'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('skill instructions')

    def entries(self, expected):
        card = dict(number=1, status='Ready', labels=['feature'], body='')
        process = subprocess.run(
            [sys.executable, str(CLI), '--root', str(self.root), '--host', 'claude', '--home', str(self.home),
             '--cards', '-'], input=json.dumps([card]), text=True, capture_output=True)
        self.assertEqual(process.returncode, expected, process.stderr)
        return json.loads(process.stdout)['entries']

    def test_qa_requires_pr_security_review_and_review_does_not(self):
        entries = self.entries(0)
        qa = {e['name']: e for e in entries if e['lane'] == 'qa'}
        review = {e['name'] for e in entries if e['lane'] == 'review'}
        self.assertEqual(qa['pr-security-review']['requirement'], 'required')
        self.assertEqual(qa['pr-security-review']['status'], 'resolved')
        self.assertNotIn('pr-security-review', review)

    def test_missing_skill_blocks_qa_only(self):
        (self.root / '.claude/skills/pr-security-review/SKILL.md').unlink()
        missing = [(e['lane'], e['name']) for e in self.entries(10) if e['status'] == 'missing']
        self.assertIn(('qa', 'pr-security-review'), missing)
        self.assertNotIn(('review', 'pr-security-review'), missing)

    def test_setup_core_lists_the_skill(self):
        text = (ROOT / '.claude/bin/super-board-setup.py').read_text()
        self.assertIn('"pr-security-review"', text.split('SKILLS = [', 1)[1].split(']', 1)[0])


if __name__ == '__main__':
    unittest.main()
