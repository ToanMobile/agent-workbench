// #1412: app Open Design chay agent `claude` voi tai khoan ghi cung trong app-config.json
// (agentCliEnv.claude.CLAUDE_CONFIG_DIR), cung tai khoan voi 5 repo ma /cc-switcher khong cho thay. Trang phai co dong
// "Open Design (app)" trong bang Repo <-> Tai khoan, doi duoc tai khoan bang cach ghi lai dung khoa do.
// Test chi dung file gia: khong doc/ghi ~/Library/Application Support/Open Design that.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DEFAULT_PROFILES, getStatusReport } from '../src/profiles.js';
import { buildPanelState, runPanelAction } from '../src/panel.js';
import { formatStatusText } from '../src/status-text.js';

const BIN = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'cc-switcher-mcp.js');
const noDaemon = () => ({ running: false, pids: [] });
const dirOf = (id) => DEFAULT_PROFILES.find((p) => p.id === id).configDir;
const ROW = 'Open Design (app)';

function fixture(claudeDir = '~/.claude-finos_team') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-od-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  const file = path.join(dir, 'app-config.json');
  const config = {
    agentCliEnv: { claude: { CLAUDE_CONFIG_DIR: claudeDir, KEEP_ME: '1' }, codex: { CODEX_HOME: '/x/.codex' } },
    agentId: 'claude',
    agentModels: { claude: { model: 'fable', effort: 'high' } },
    installationId: 'abc-123',
    telemetry: { enabled: false },
  };
  fs.writeFileSync(file, JSON.stringify(config, null, 2), { mode: 0o644 });
  const opts = { stateDir: dir, repos: [], openDesignConfig: file, daemonProbe: noDaemon, sync: false };
  return { dir, file, config, opts, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}
const odRow = (st) => st.repoAssignments.find((r) => r.name === ROW);

test('panel JSON co dong Open Design voi tai khoan finos_linh va tinh vao so repo dang gan', async () => {
  const f = fixture();
  try {
    const st = await buildPanelState(f.opts);
    const row = odRow(st);
    assert.ok(row, 'thieu dong Open Design (app)');
    assert.equal(row.account, 'finos_linh');
    assert.equal(row.pinnedInFile, true);
    assert.equal(row.source, 'app');
    assert.equal(row.path, f.file);
    assert.equal(row.effective.kind, 'assigned');
    // so repo dang gan = so cua cac repo (khong co Open Design) + 1 cho dung tai khoan Open Design dang dung
    const base = await buildPanelState({ ...f.opts, openDesignConfig: undefined });
    const count = (s, id) => s.profiles.find((p) => p.id === id).assignedRepoCount;
    assert.equal(odRow(base), undefined);
    assert.equal(count(st, 'finos_linh'), count(base, 'finos_linh') + 1);
    assert.equal(count(st, 'finos_toan'), count(base, 'finos_toan'));
    assert.ok(!JSON.stringify(st).includes('configDir'));
    assert.match(formatStatusText(getStatusReport({ stateDir: f.dir, repos: [], openDesignConfig: f.file })), /finos_linh: .*Open Design \(app\)/);
  } finally { f.cleanup(); }
});

test('duong dan tuyet doi (dang file that dang ghi) cung doi ra dung tai khoan', async () => {
  const f = fixture(dirOf('finos_lua'));
  try {
    assert.equal(odRow(await buildPanelState(f.opts)).account, 'finos_lua');
  } finally { f.cleanup(); }
});

test('doi sang finos_toan: ghi dung mot khoa, cac khoa khac va mode file nguyen ven', async () => {
  const f = fixture();
  try {
    const res = await runPanelAction('repo_assign', { repo: f.file, account: 'finos_toan' }, f.opts);
    assert.equal(res.ok, true);
    assert.equal(res.repo.previous, 'finos_linh');
    assert.equal(res.repo.account, 'finos_toan');
    const after = JSON.parse(fs.readFileSync(f.file, 'utf8'));
    assert.equal(after.agentCliEnv.claude.CLAUDE_CONFIG_DIR, dirOf('finos_toan'));
    const expected = structuredClone(f.config);
    expected.agentCliEnv.claude.CLAUDE_CONFIG_DIR = dirOf('finos_toan');
    assert.deepEqual(after, expected);
    assert.equal(fs.statSync(f.file).mode & 0o777, 0o644);
    assert.deepEqual(fs.readdirSync(f.dir).filter((n) => n.startsWith('app-config.json') && n !== 'app-config.json'), []);
    assert.equal(odRow(await buildPanelState(f.opts)).account, 'finos_toan');
    // id cu van nhan, ghi ra thu muc cua id moi
    await runPanelAction('repo_assign', { repo: f.file, account: 'finos_team' }, f.opts);
    assert.equal(JSON.parse(fs.readFileSync(f.file, 'utf8')).agentCliEnv.claude.CLAUDE_CONFIG_DIR, dirOf('finos_linh'));
  } finally { f.cleanup(); }
});

test('chi nhan tai khoan Claude; dong app khong go duoc', async () => {
  const f = fixture();
  try {
    const before = fs.readFileSync(f.file, 'utf8');
    await assert.rejects(runPanelAction('repo_assign', { repo: f.file, account: 'antigravity_ultra' }, f.opts), /tài khoản Claude/);
    await assert.rejects(runPanelAction('repo_remove', { repo: f.file }, f.opts), (err) => err.code === 'INVALID_INPUT');
    assert.equal(fs.readFileSync(f.file, 'utf8'), before);
  } finally { f.cleanup(); }
});

test('file hong hoac khong phai JSON object: khong ghi, tra loi INVALID_INPUT, trang van bao', async () => {
  for (const broken of ['{"agentCliEnv": {', '["not", "an", "object"]', '{"agentCliEnv": "nope"}']) {
    const f = fixture();
    try {
      fs.writeFileSync(f.file, broken);
      await assert.rejects(
        runPanelAction('repo_assign', { repo: f.file, account: 'finos_toan' }, f.opts),
        (err) => err.code === 'INVALID_INPUT' && /app-config\.json/.test(err.message),
      );
      assert.equal(fs.readFileSync(f.file, 'utf8'), broken);
      const row = odRow(await buildPanelState(f.opts));
      assert.ok(row, 'file hong van phai co dong de bao');
      assert.equal(row.account, '');
      assert.equal(row.differs, true);
      assert.match(row.effective.note, /app-config\.json/);
    } finally { f.cleanup(); }
  }
});

test('chua dat CLAUDE_CONFIG_DIR hoac thu muc la: dong hien chua ghim / khong ro, gan duoc tai khoan', async () => {
  const f = fixture('/somewhere/else/.claude-x');
  try {
    const row = odRow(await buildPanelState(f.opts));
    assert.equal(row.account, '');
    assert.match(row.effective.note, /\.claude-x/);
    const cfg = JSON.parse(fs.readFileSync(f.file, 'utf8'));
    delete cfg.agentCliEnv;
    fs.writeFileSync(f.file, JSON.stringify(cfg));
    assert.equal(odRow(await buildPanelState(f.opts)).effective.kind, 'unpinned');
    await runPanelAction('repo_assign', { repo: f.file, account: 'finos_lua' }, f.opts);
    const after = JSON.parse(fs.readFileSync(f.file, 'utf8'));
    assert.deepEqual(after.agentCliEnv, { claude: { CLAUDE_CONFIG_DIR: dirOf('finos_lua') } });
    assert.equal(after.agentId, 'claude');
  } finally { f.cleanup(); }
});

test('thu muc trang thai co lap khong doc config that; khong co file thi khong co dong', async () => {
  const f = fixture();
  try {
    const st = await buildPanelState({ stateDir: f.dir, repos: [], daemonProbe: noDaemon, sync: false });
    assert.equal(odRow(st), undefined);
    fs.rmSync(f.file);
    assert.equal(odRow(await buildPanelState(f.opts)), undefined);
  } finally { f.cleanup(); }
});

test('CLI cua Agent Office: bien CC_SWITCHER_OPEN_DESIGN_CONFIG chi file, --panel-json va --panel-action dung chung', () => {
  const f = fixture();
  try {
    const run = (...args) => JSON.parse(execFileSync(process.execPath, [BIN, ...args, '--state-dir', f.dir], {
      encoding: 'utf8', env: { ...process.env, CC_SWITCHER_OPEN_DESIGN_CONFIG: f.file }, stdio: ['ignore', 'pipe', 'ignore'],
    }));
    assert.equal(odRow(run('--panel-json', '--no-sync')).account, 'finos_linh');
    const res = run('--panel-action', 'repo_assign', '--repo', f.file, '--account', 'finos_toan_max');
    assert.equal(res.ok, true);
    assert.equal(odRow(res.state).account, 'finos_toan_max');
    assert.equal(JSON.parse(fs.readFileSync(f.file, 'utf8')).agentCliEnv.claude.CLAUDE_CONFIG_DIR, dirOf('finos_toan_max'));
  } finally { f.cleanup(); }
});
