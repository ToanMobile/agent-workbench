// Smoke test: run the page's script against a tiny fake DOM and check that every section gets drawn.
// usage: node render_smoke.js   (exit 0 = pass). No browser or npm package needed.
const fs = require('fs');
const path = require('path');

const here = __dirname;
const rows = JSON.parse(fs.readFileSync(path.join(here, 'checks.json'), 'utf8'));
const page = fs.readFileSync(path.join(here, 'workflow-map.page.html'), 'utf8');
const script = page.match(/<script>([\s\S]*)<\/script>/)[1];
const markup = page.replace(/<style>[\s\S]*?<\/style>/, '').replace(/<script>[\s\S]*<\/script>/, '');

class Node_ {
  constructor(tag) { this.tag = tag; this.children = []; this.dataset = {}; this.className = ''; this.hidden = false; this._text = ''; this.listeners = {}; this.attrs = {}; }
  setAttribute(k, v) { this.attrs[k] = String(v); if (k === 'class') this.className = String(v); }
  appendChild(c) { this.children.push(c); return c; }
  append(...cs) { cs.forEach((c) => this.children.push(typeof c === 'string' ? Object.assign(new Node_('#text'), { _text: c }) : c)); }
  replaceChildren(...cs) { this.children = []; this.append(...cs); }
  addEventListener(ev, fn) { this.listeners[ev] = fn; }
  set textContent(v) { this._text = String(v); this.children = []; }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(''); }
  walk(fn) { fn(this); this.children.forEach((c) => c.walk(fn)); }
}

const byId = new Map();
for (const m of markup.matchAll(/<(\w+)[^>]*\sid="([^"]+)"/g)) {
  const n = new Node_(m[1]);
  n.hidden = /hidden/.test(m[0]);
  n.checked = /checked/.test(m[0]);
  byId.set(m[2], n);
}
global.document = {
  getElementById: (id) => byId.get(id),
  createElement: (t) => new Node_(t),
  createElementNS: (ns, t) => new Node_(t),
  createTextNode: (t) => Object.assign(new Node_('#text'), { _text: t }),
};

const calcs = new Map([['checks', rows]]);
let draws = 0;
global.dash = {
  data: (id) => (calcs.has(id) ? { status: 'ok', data: calcs.get(id) } : { status: 'missing', data: [] }),
  calc: (id, spec) => calcs.set(id, spec.fn(...spec.inputs.map((i) => calcs.get(i)))),
  onData: (fn) => { draws += 1; fn(); },
};

const fail = [];
const expect = (name, ok) => { if (!ok) fail.push(name); };
// elements the flow section needs: a missing one is a failed assertion, not a crash. They are stood in BEFORE the page script
// runs, because the script binds listeners to them while it loads
['dc-flow', 'dc-branches', 'dc-stepno', 'dc-caption', 'dc-prev', 'dc-next', 'dc-play', 'dc-hookdetail', 'dc-localhooks'].forEach((id) => {
  if (!byId.has(id)) { expect('page has #' + id, false); byId.set(id, new Node_('missing')); }
});

// the page keeps its inline script in its own scope, exactly like the dashboard runtime does
new Function(script)();

const find = (id, pred) => { const out = []; byId.get(id).walk((x) => { if (pred(x)) out.push(x); }); return out; };

const repos = new Set(rows.map((r) => r.repo)).size;
const body = (id) => byId.get(id).children.find((c) => c.tag === 'tbody');
expect('onData registered once', draws === 1);
const nodes = find('dc-diagram', (x) => x.tag === 'g' && x.className.split(' ').includes('node'));
const squares = find('dc-diagram', (x) => x.tag === 'rect' && x.className.split(' ').includes('sq'));
const flowRows = new Set(rows.filter((r) => r.area === 'flow').map((r) => r.group + '|' + r.item)).size;
expect('diagram has 8 phase nodes', nodes.length === 8);
expect('diagram has one square per repo and component', squares.length === repos * flowRows);
expect('diagram draws the Stop-gate loop', find('dc-diagram', (x) => x.tag === 'path' && x.className === 'loop').length === 1);
expect('diagram has an arrow between neighbouring phases', find('dc-diagram', (x) => x.tag === 'line' && x.className === 'flowline').length === 7);
expect('detail lists components', body('dc-detail').children.length >= 4);
expect('detail has a column per repo', find('dc-detail', (x) => x.tag === 'th').length === 2 + repos);
expect('mcp table lists the required servers', body('dc-mcp').children.length >= 5);
// the ocr remark appears exactly when the data says no hook runs ocr (that is what the page tests; it is absent while review_gate.sh runs it)
const ocrRow = rows.find((r) => r.area === 'tool' && r.item === 'ocr');
expect('take line names ocr only while no hook runs it', byId.get('dc-take').textContent.includes('ocr') === (!!ocrRow && (ocrRow.trigger || '').indexOf('không hook') === 0));
expect('todo list is filled', find('dc-todo', (x) => x.tag === 'li').length > 0);

// choosing another phase must redraw the detail
const before = byId.get('dc-dtitle').textContent;
const other = find('dc-diagram', (x) => x.tag === 'g' && x.className.split(' ').includes('node'))
  .find((g) => !before.includes(g.attrs['aria-label'].replace(/^Bước \d+: /, '')));
other.listeners.click();
expect('clicking a phase changes the detail title', byId.get('dc-dtitle').textContent !== before);

// ---- the event-lane flow ("Đường đi của một việc"): built from the real hook rows, not typed by hand ----
const hookRows = rows.filter((r) => r.area === 'hook');
expect('every hook row carries its declaration order', hookRows.length > 0 && hookRows.every((r) => typeof r.order === 'number'));
// the lanes show the kit's own chain (order < 1000, a node per event + matcher + script); a repo's extra hooks are listed apart
const kitRows = hookRows.filter((r) => r.order < 1000);
const localRows = hookRows.filter((r) => r.order >= 1000);
const distinct = (ev) => new Set(kitRows.filter((r) => r.group === ev).map((r) => r.trigger + '|' + r.item)).size;
const hnodes = find('dc-flow', (x) => x.tag === 'g' && x.className.split(' ').includes('hnode'));
const ofEvent = (ev) => hnodes.filter((g) => g.attrs['data-event'] === ev);
['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'Notification', 'SessionEnd'].forEach((ev) => {
  expect('flow has one node per ' + ev + ' hook (' + distinct(ev) + ')', ofEvent(ev).length === distinct(ev) && distinct(ev) > 0);
});
const kitKeys = new Set(kitRows.map((r) => r.group + '|' + r.trigger + '|' + r.item));
expect('every kit hook has a node, whatever its event (' + kitKeys.size + ')', hnodes.filter((g) => g.attrs['data-event'] !== 'git').length === kitKeys.size);
expect('every hook node has one status dot per repo',
  hnodes.length > 0 && hnodes.every((g) => g.children.filter((c) => c.tag === 'rect' && c.className.split(' ').includes('sq')).length === repos));
const rejects = find('dc-flow', (x) => x.tag === 'path' && x.className.split(' ').includes('reject'));
expect('every Stop gate has its own reject edge', rejects.length === distinct('Stop') && new Set(rejects.map((p) => p.attrs['data-gate'])).size === distinct('Stop'));
// no repo-only hook at all is a valid state: the page then shows one placeholder line
expect('repo-only hooks are listed apart, one line each', find('dc-localhooks', (x) => x.tag === 'li').length === Math.max(1, localRows.length));
expect('flow has a lane label per stage', find('dc-flow', (x) => x.tag === 'text' && x.className.split(' ').includes('lane')).length >= 6);
expect('flow draws the tool loop back to the agent', find('dc-flow', (x) => x.tag === 'path' && x.className.split(' ').includes('loop')).length >= 1);
const cards = byId.get('dc-branches').children;
expect('three branch cards', cards.length === 3);
expect('each branch card is a chain of >= 3 steps', cards.every((c) => { let n = 0; c.walk((x) => { if (x.className.split(' ').includes('bstep')) n += 1; }); return n >= 3; }));

// layout: no two boxes overlap, every box sits inside one lane band, the viewBox is tall enough for the last band
const num = (n, k) => Number(n.attrs[k]);
const boxes = find('dc-flow', (x) => x.tag === 'rect' && x.className.split(' ').includes('box')).map((r) => ({ x: num(r, 'x'), y: num(r, 'y'), w: num(r, 'width'), h: num(r, 'height') }));
const bands = find('dc-flow', (x) => x.tag === 'rect' && x.className.split(' ').includes('laneband')).map((r) => ({ x: num(r, 'x'), y: num(r, 'y'), w: num(r, 'width'), h: num(r, 'height') }));
expect('flow has boxes and lane bands', boxes.length > 0 && bands.length >= 6);
expect('no two flow boxes overlap', boxes.every((a, i) => boxes.every((b, j) => i >= j || a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)));
expect('every flow box sits inside one lane band', boxes.every((b) => bands.some((l) => b.x >= l.x && b.x + b.w <= l.x + l.w && b.y >= l.y && b.y + b.h <= l.y + l.h)));
const vbH = Number(((byId.get('dc-flow').attrs.viewBox || '').split(' ')[3]));
expect('viewBox covers the last lane band', bands.length > 0 && Math.max(...bands.map((l) => l.y + l.h)) <= vbH);

// the stepper walks one task through the whole flow
const click = (id) => { const fn = byId.get(id).listeners.click; if (fn) fn(); };
const stepNo = () => byId.get('dc-stepno').textContent;
const total = Number((stepNo().match(/\/(\d+)/) || [])[1]);
expect('stepper has 10 or more steps', total >= 10);
expect('previous is disabled on the first step', byId.get('dc-prev').disabled === true);
const captions = new Set([byId.get('dc-caption').textContent]);
let stopLit = false;
for (let i = 1; i < total; i += 1) {
  click('dc-next');
  captions.add(byId.get('dc-caption').textContent);
  if (byId.get('dc-caption').attrs['data-step'] === 'stop') {
    stopLit = ofEvent('Stop').length > 0 && ofEvent('Stop').every((g) => g.className.split(' ').includes('on'))
      && hnodes.filter((g) => g.attrs['data-event'] !== 'Stop').every((g) => !g.className.split(' ').includes('on'));
  }
}
expect('every step has its own caption', captions.size === total);
expect('the Stop step lights every Stop gate', stopLit);
expect('next is disabled on the last step', byId.get('dc-next').disabled === true);
click('dc-prev');
expect('previous goes back one step', stepNo() === 'Bước ' + (total - 1) + '/' + total);

// choosing a hook shows what it is and where each repo stands
const pick = ofEvent('Stop')[0];
if (pick && pick.listeners.click) pick.listeners.click();
expect('clicking a hook shows its detail', !!pick && !!pick.attrs['data-hook'] && byId.get('dc-hookdetail').textContent.includes(pick.attrs['data-hook']));

// the 8-phase view names the real events of its hooks (read_ledger is PostToolUse, not PreToolUse)
const p3 = find('dc-diagram', (x) => x.tag === 'g' && x.className.split(' ').includes('node'))[2];
expect('phase 3 lists PostToolUse (read_ledger)', !!p3 && p3.children.filter((c) => c.tag === 'text').some((c) => c.textContent.includes('PostToolUse')));

if (fail.length) { process.stderr.write('FAIL: ' + fail.join('; ') + '\n'); process.exit(1); }
process.stdout.write('render_smoke: PASS (' + repos + ' repos, ' + rows.length + ' rows)\n');
