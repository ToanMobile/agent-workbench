// Kiểm tra giao diện thật trong Chromium (playwright-core): thanh nút đúng MỘT hàng, menu ⋯, ô tài khoản góc phải trên.
// Chạy: PLAYWRIGHT_CORE=<thư mục playwright-core> node tests/ui_toolbar_account.js [--shots <thư mục>]
// (test_ui_toolbar_account.py gọi file này và bỏ qua khi máy không có playwright-core / Chromium.)
'use strict';
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), net = require('net');
const HERE = path.dirname(__dirname);
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const shotsAt = process.argv.indexOf('--shots'); const SHOTS = shotsAt > 0 ? process.argv[shotsAt + 1] : null;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function chromiumPath() {
  if (process.env.PW_CHROMIUM) return process.env.PW_CHROMIUM;
  const base = path.join(os.homedir(), 'Library', 'Caches', 'ms-playwright');
  try {
    for (const d of fs.readdirSync(base).filter((x) => /^chromium-\d+$/.test(x)).sort().reverse()) {
      for (const sub of ['chrome-mac-arm64', 'chrome-mac']) {
        const p = path.join(base, d, sub, 'Google Chrome for Testing.app', 'Contents', 'MacOS', 'Google Chrome for Testing');
        if (fs.existsSync(p)) return p;
      }
    }
  } catch (e) { /* không phải macOS: để playwright tự tìm */ }
  return undefined;
}
const freePort = () => new Promise((res) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });

const FORMER = ['btnApprove', 'btnAgents', 'btnFit', 'btnZoom', 'btnRail', 'btnBoard', 'btnAdd', 'btnEvents', 'btnDash', 'btnNext', 'btnDesk', 'btnTheme', 'btnPhone', 'btnRefresh'];
const VIEWS = [[390, 844], [768, 1024], [1024, 768], [1280, 800], [1440, 900]];
const fails = []; const report = {};
const check = (cond, msg) => { if (!cond) fails.push(msg); return cond; };

async function measure(page) {
  return page.evaluate((former) => {
    const vis = (el) => { if (!el || el.closest('[hidden]')) return false; const s = getComputedStyle(el); const r = el.getBoundingClientRect(); return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0; };
    const box = (el) => { const r = el.getBoundingClientRect(); return { l: Math.round(r.left), t: Math.round(r.top), r: Math.round(r.right), b: Math.round(r.bottom), w: Math.round(r.width), h: Math.round(r.height) }; };
    const c = document.querySelector('.controls');
    const btns = [...c.querySelectorAll('button')].filter(vis);
    const tops = [...new Set(btns.map((b) => Math.round(b.getBoundingClientRect().top + b.getBoundingClientRect().height / 2)))];
    const rowSpread = tops.length ? Math.max(...tops) - Math.min(...tops) : 0;
    const cr = c.getBoundingClientRect();
    const clipped = btns.filter((b) => { const r = b.getBoundingClientRect(); return r.left < cr.left - 0.5 || r.right > cr.right + 0.5 || r.left < 0 || r.right > innerWidth; }).map((b) => b.id);
    const menu = document.getElementById('moreMenu');
    const menuVis = vis(menu);
    const items = menuVis ? [...menu.querySelectorAll('[role^="menuitem"]')].filter(vis) : [];
    const reach = {};
    for (const id of former) {
      const el = document.getElementById(id);
      const inBar = el && c.contains(el) && vis(el);
      const asItem = menuVis && items.some((m) => m.id === id || m.dataset.for === id);
      reach[id] = inBar ? 'toolbar' : asItem ? 'menu' : null;
    }
    const pick = (s) => { const el = document.querySelector(s); return vis(el) ? box(el) : null; };
    return {
      W: innerWidth, docScrollW: document.documentElement.scrollWidth,
      controls: { ...box(c), scrollW: c.scrollWidth, clientW: c.clientWidth, rowSpread, buttons: btns.map((b) => b.id || b.textContent.trim()), clipped, btnH: Math.max(0, ...btns.map((b) => b.getBoundingClientRect().height)) },
      menu: menuVis ? { ...box(menu), role: menu.getAttribute('role'), items: items.map((m) => m.id || m.dataset.for), offscreen: items.filter((m) => { const r = m.getBoundingClientRect(); return r.right > innerWidth || r.left < 0 || r.bottom > innerHeight; }).map((m) => m.id || m.dataset.for) } : null,
      reach, chip: pick('#acctChip'), brand: pick('.brand'), legend: pick('#legend'), zoom: pick('.zoom-ctl'), drawer: pick('#drawer'), banner: pick('#apprBanner'),
      chipText: document.getElementById('acctChip').innerText.replace(/\s+/g, ' ').trim(),
    };
  }, FORMER);
}
const overlap = (a, b) => a && b && Math.min(a.r, b.r) - Math.max(a.l, b.l) > 0 && Math.min(a.b, b.b) - Math.max(a.t, b.t) > 0;

function checkBar(m, tag) {
  const c = m.controls;
  check(c.scrollW <= c.clientW, `${tag}: thanh nút cuộn ngang ẩn (scrollWidth ${c.scrollW} > clientWidth ${c.clientW})`);
  check(c.rowSpread <= 2, `${tag}: nút không cùng một hàng (lệch ${c.rowSpread}px)`);
  check(c.h <= c.btnH + 16, `${tag}: thanh cao ${c.h}px, hơn một hàng nút (${c.btnH}px)`);
  check(!c.clipped.length, `${tag}: nút bị cắt ${c.clipped.join(',')}`);
  check(c.l >= 0 && c.r <= m.W, `${tag}: thanh ra ngoài màn hình`);
  check(m.docScrollW <= m.W, `${tag}: trang cuộn ngang (${m.docScrollW} > ${m.W})`);
}
function checkChip(m, tag) {
  const k = m.chip;
  if (!check(!!k, `${tag}: không thấy ô tài khoản`)) return;
  check(m.W - k.r <= 16 && k.t <= 24, `${tag}: ô tài khoản không ở góc phải trên (${JSON.stringify(k)})`);
  for (const [n, b] of [['header', m.brand], ['legend', m.legend], ['zoom', m.zoom], ['drawer', m.drawer], ['toolbar', m.controls]]) check(!overlap(k, b), `${tag}: ô tài khoản đè ${n}`);
}

if (process.argv.includes('--probe')) { // test_ui_toolbar_account.py: có trình duyệt chạy được không
  const exe = chromiumPath() || pw.chromium.executablePath();
  process.exit(exe && fs.existsSync(exe) ? 0 : 3);
}
(async () => {
  const port = await freePort();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ao-ui-'));
  const cfgPath = path.join(tmp, 'config.json');
  fs.writeFileSync(cfgPath, JSON.stringify({ host: '127.0.0.1', port, macNotify: false, eventsFile: path.join(tmp, 'events.jsonl'), inboxDir: path.join(tmp, 'inbox'), resumeLogDir: path.join(tmp, 'resume') }));
  const srv = spawn('python3', [path.join(HERE, 'server.py'), '--demo', '--config', cfgPath, '--port', String(port)], { stdio: ['ignore', 'pipe', 'pipe'] });
  let srvOut = ''; srv.stdout.on('data', (d) => { srvOut += d; }); srv.stderr.on('data', (d) => { srvOut += d; });
  const URL_ = `http://127.0.0.1:${port}/`;
  for (let i = 0; i < 100 && !/đang chạy/.test(srvOut); i++) await sleep(100);
  const browser = await pw.chromium.launch({ executablePath: chromiumPath(), headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const shoot = async (page, name) => { if (SHOTS) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, name + '.png'), timeout: 90000 }); } };
    const open = async (w, h, scheme, mutate) => {
      const ctx = await browser.newContext({ viewport: { width: w, height: h }, colorScheme: scheme });
      await ctx.addInitScript(() => { try { localStorage.setItem('agent-office-hint-nav2', '1'); } catch (e) { /* */ } });
      await ctx.route('**/api/**', async (r) => {
        const u = r.request().url();
        if (r.request().method() !== 'GET' || /\/api\/(refresh|phone)/.test(u)) return r.abort(); // không chạy tunnel/ghi gì thật
        if (mutate && /\/api\/state/.test(u)) { const res = await r.fetch(); const j = await res.json(); mutate(j); return r.fulfill({ response: res, json: j }); }
        return r.continue();
      });
      const page = await ctx.newPage();
      await page.goto(URL_, { waitUntil: 'load' });
      await page.waitForFunction(() => document.getElementById('boot').hidden, null, { timeout: 60000 });
      await sleep(1500);
      return { ctx, page };
    };
    for (const [w, h] of VIEWS) {
      for (const scheme of (w === 1440 ? ['light', 'dark'] : ['light'])) {
        const tag = `${w}-${scheme}`; const { ctx, page } = await open(w, h, scheme);
        const closed = await measure(page); report[tag] = { closed };
        checkBar(closed, tag + ' menu đóng'); checkChip(closed, tag);
        const mobile = w < 900;
        if (mobile) check(['btnBoard', 'btnAdd', 'btnMore'].every((id) => closed.controls.buttons.includes(id)) && closed.controls.buttons.every((id) => ['btnApprove', 'btnBoard', 'btnAdd', 'btnMore'].includes(id)), `${tag}: thanh điện thoại phải là Duyệt/Bảng/Thêm/⋯, thấy ${closed.controls.buttons}`);
        else check(!closed.controls.buttons.includes('btnApprove'), `${tag}: máy tính không còn nút Duyệt trùng băng "Duyệt ›"`);
        if (mobile) check(closed.controls.buttons.includes('btnApprove'), `${tag}: còn thẻ chờ duyệt mà điện thoại không có nút Duyệt`);
        else check(!!closed.banner, `${tag}: băng "Duyệt ›" phải hiện khi có thẻ chờ`);
        await shoot(page, `ui-${tag}`);
        // menu ⋯ bằng chuột
        await page.click('#btnMore');
        const opened = await measure(page); report[tag].open = opened;
        if (check(!!opened.menu && opened.menu.role === 'menu', `${tag}: ⋯ không mở menu role=menu`)) {
          checkBar(opened, tag + ' menu mở');
          check(!opened.menu.offscreen.length && opened.menu.r <= w && opened.menu.l >= 0, `${tag}: mục menu ra ngoài màn hình ${opened.menu.offscreen}`);
          const lost = Object.entries(opened.reach).filter(([id, v]) => !v && !(id === 'btnApprove' && closed.banner)).map(([id]) => id);
          check(!lost.length, `${tag}: thao tác cũ không còn lối vào: ${lost.join(', ')}`);
          check(await page.evaluate(() => document.activeElement && document.activeElement.closest('#moreMenu') !== null), `${tag}: mở menu không đưa focus vào mục đầu`);
        }
        await shoot(page, `ui-${tag}-menu`);
        await page.mouse.click(Math.round(w / 2), Math.round(h / 2)); await sleep(150);
        check(await page.evaluate(() => document.getElementById('moreMenu').hidden), `${tag}: bấm ra ngoài không đóng menu`);
        // bàn phím: ↓ trên ⋯ mở, ↓ đi mục kế, End, Esc đóng và trả focus
        await page.focus('#btnMore'); await page.keyboard.press('ArrowDown');
        const k1 = await page.evaluate(() => document.activeElement.textContent.trim());
        await page.keyboard.press('ArrowDown'); const k2 = await page.evaluate(() => document.activeElement.textContent.trim());
        await page.keyboard.press('End'); const k3 = await page.evaluate(() => document.activeElement.textContent.trim());
        check(k1 !== k2 && /Tải lại GitHub/.test(k3), `${tag}: phím mũi tên/End trong menu (${k1} → ${k2} → ${k3})`);
        await page.keyboard.press('Escape');
        check(await page.evaluate(() => document.getElementById('moreMenu').hidden && document.activeElement.id === 'btnMore'), `${tag}: Esc không đóng menu / không trả focus về ⋯`);
        // mục trong menu chạy được: Ca đêm bật/tắt theme, giữ phím tắt N
        const before = await page.evaluate(() => document.documentElement.dataset.theme);
        await page.click('#btnMore'); await page.click('#btnTheme'); await sleep(300);
        const after = await page.evaluate(() => [document.documentElement.dataset.theme, document.getElementById('btnTheme').getAttribute('aria-checked')]);
        check(after[0] !== before && after[1] === String(after[0] === 'dark'), `${tag}: "Ca đêm" trong menu không đổi theme (${before} → ${after})`);
        await page.click('#btnMore'); await page.click('#btnTheme'); await sleep(300);
        await page.keyboard.press('n'); await sleep(300);
        check(await page.evaluate(() => !document.getElementById('drawer').hidden), `${tag}: phím N (Agent kế tiếp) không mở agent`);
        await page.keyboard.press('Escape'); await sleep(200);
        // nút bật/tắt giữ nhãn cố định
        const bw0 = await page.evaluate(() => [document.getElementById('btnBoard').getBoundingClientRect().width, document.getElementById('btnBoard').textContent]);
        await page.keyboard.press('b'); await sleep(300);
        const bw1 = await page.evaluate(() => [document.getElementById('btnBoard').getBoundingClientRect().width, document.getElementById('btnBoard').textContent, document.getElementById('btnBoard').getAttribute('aria-pressed')]);
        check(bw0[0] === bw1[0] && bw0[1] === bw1[1] && bw1[2] === 'true', `${tag}: Dạng bảng đổi nhãn/bề ngang hoặc thiếu aria-pressed`);
        const boardBar = await measure(page); checkBar(boardBar, tag + ' dạng bảng');
        await page.keyboard.press('b'); await sleep(200);
        // ô tài khoản: popover, bấm dòng mở drawer
        await page.click('#acctChip'); await sleep(200);
        const pop = await page.evaluate(() => { const p = document.getElementById('acctPop'); const r = p.getBoundingClientRect(); return { hidden: p.hidden, rows: p.querySelectorAll('.ap-row').length, text: p.innerText, r: Math.round(r.right), l: Math.round(r.left), b: Math.round(r.bottom), focus: document.activeElement.className, expanded: document.getElementById('acctChip').getAttribute('aria-expanded') }; });
        report[tag].pop = pop;
        check(!pop.hidden && pop.rows > 0 && /finos/.test(pop.text) && /triệu token/.test(pop.text), `${tag}: popover tài khoản thiếu dòng/tài khoản/token`);
        check(pop.r <= w && pop.l >= 0 && pop.b <= h, `${tag}: popover tài khoản ra ngoài màn hình`);
        check(pop.expanded === 'true' && /ap-row/.test(pop.focus), `${tag}: popover thiếu aria-expanded/focus dòng đầu`);
        await shoot(page, `ui-${tag}-account`);
        await page.click('#acctPop .ap-row:has(.ap-acc:text-matches("finos|max"))');
        await sleep(400);
        const withDrawer = await measure(page); report[tag].drawer = withDrawer;
        check(!!withDrawer.drawer && (await page.evaluate(() => document.getElementById('acctPop').hidden)), `${tag}: bấm dòng không mở drawer agent`);
        check(/Tài khoản/.test(await page.evaluate(() => document.getElementById('drawer').innerText)), `${tag}: drawer agent thiếu dòng Tài khoản`);
        checkChip(withDrawer, tag + ' khi mở drawer');
        await page.keyboard.press('Escape');
        await ctx.close();
      }
    }
    // trạng thái rỗng
    const { ctx, page } = await open(1280, 800, 'light', (j) => { j.workers = []; });
    const em = await measure(page);
    check(/Chưa có phiên/.test(em.chipText), `trạng thái rỗng: ô tài khoản ghi "${em.chipText}"`);
    await page.click('#acctChip');
    check(/Chưa có phiên/.test(await page.evaluate(() => document.getElementById('acctPop').innerText)), 'trạng thái rỗng: popover không báo chưa có phiên');
    await ctx.close();
  } finally {
    await browser.close(); srv.kill();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  if (process.env.UI_REPORT) fs.writeFileSync(process.env.UI_REPORT, JSON.stringify(report, null, 1));
  if (fails.length) { console.error('UI FAIL\n- ' + fails.join('\n- ')); process.exit(1); }
  console.log('UI OK: ' + Object.keys(report).join(', '));
})().catch((e) => { console.error(e); process.exit(2); });
