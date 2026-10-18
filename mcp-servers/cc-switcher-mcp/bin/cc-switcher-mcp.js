#!/usr/bin/env node
// Entrypoint cho cc-switcher-mcp: ho tro chay MCP server (stdio), chay Daemon ngam (--daemon), hoac CLI (--doctor, --status, --switch, --rotate).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const localModules = path.resolve(__dirname, '..', 'node_modules');
const sharedModules = path.resolve(__dirname, '..', '..', 'antigravity-pm-mcp', 'node_modules');
if (!fs.existsSync(localModules) && fs.existsSync(sharedModules)) {
  try {
    fs.symlinkSync(sharedModules, localModules, 'dir');
  } catch (err) {
    if (err?.code !== 'EEXIST') {
      process.stderr.write(`[cc-switcher-mcp] symlink warning: ${err?.message}\n`);
    }
  }
}

const { main } = await import('../src/server.js');
const { TOOLS_BY_NAME } = await import('../src/tools.js');
const { startSwitcherDaemon } = await import('../src/daemon.js');
const { logStructured } = await import('../src/errors.js');

// Dang ky bat loi toan cuc tai entrypoint (tuan thu Node.js production rules).
process.on('unhandledRejection', (reason) => {
  logStructured('error', 'unhandled_rejection', {
    reason: reason instanceof Error ? reason.message : String(reason),
  });
});

process.on('uncaughtException', (err) => {
  logStructured('error', 'uncaught_exception', {
    message: err?.message || String(err),
    code: err?.code,
  });
  process.exit(1);
});

const argv = process.argv.slice(2);

if (argv.includes('--help') || argv.includes('-h')) {
  process.stdout.write(`cc-switcher-mcp — MCP Server & Auto-Switcher Daemon chong ban cho 6 profile CC Switch

Cach dung:
  (khong tham so)           Chay MCP server qua giao thuc stdio
  --daemon                  Chay Daemon theo doi log 429 & dieu khien 2 chieu qua Telegram Bot
  --doctor / --status       In trang thai 6 profile, Cooldown va thong ke token/chi phi
  --switch <1..6|id>        Chuyen nhanh sang profile chi dinh
  --rotate                  Xoay vong sang profile an toan tiep theo
  --tools                   Liet ke danh sach MCP tools
  --help                    Hien thi tro giup
`);
  process.exit(0);
}

if (argv.includes('--tools')) {
  for (const [name, t] of TOOLS_BY_NAME) {
    process.stdout.write(`${name}\n    ${t.description}\n`);
  }
  process.exit(0);
}

if (argv.includes('--doctor') || argv.includes('--status')) {
  const out = await TOOLS_BY_NAME.get('switcher_status').handler({});
  process.stdout.write(`${out.text}\n`);
  process.exit(0);
}

if (argv.includes('--switch')) {
  const idx = argv.indexOf('--switch');
  const target = argv[idx + 1];
  const force = argv.includes('--force');
  const out = await TOOLS_BY_NAME.get('switcher_switch').handler({
    target,
    enforceCooldown: !force,
  });
  process.stdout.write(`${out.text}\n`);
  process.exit(0);
}

if (argv.includes('--rotate')) {
  const out = await TOOLS_BY_NAME.get('switcher_rotate').handler({
    markCurrentLimited: argv.includes('--limit'),
  });
  process.stdout.write(`${out.text}\n`);
  process.exit(0);
}

if (argv.includes('--daemon')) {
  await startSwitcherDaemon({});
} else {
  await main();
}
