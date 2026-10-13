// Smoke test: run the page's script against a tiny fake DOM and check that every section gets drawn.
// usage: node render_smoke.js   (exit 0 = pass). No browser or npm package needed.
const fs = require('fs');
const path = require('path');

const here = __dirname;
const rows = JSON.parse(fs.readFileSync(path.join(here, 'checks.json'), 'utf8'));
const page = fs.readFileSync(path.join(here, 'coverage-map.page.html'), 'utf8');
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

// the page keeps its inline script in its own scope, exactly like the dashboard runtime does
new Function(script)();

const find = (id, pred) => { const out = []; byId.get(id).walk((x) => { if (pred(x)) out.push(x); }); return out; };
const fail = [];
const expect = (name, ok) => { if (!ok) fail.push(name); };

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
expect('take line names ocr', byId.get('dc-take').textContent.includes('ocr'));
expect('todo list is filled', find('dc-todo', (x) => x.tag === 'li').length > 0);

// choosing another phase must redraw the detail
const before = byId.get('dc-dtitle').textContent;
const other = find('dc-diagram', (x) => x.tag === 'g' && x.className.split(' ').includes('node'))
  .find((g) => !before.includes(g.attrs['aria-label'].replace(/^Bước \d+: /, '')));
other.listeners.click();
expect('clicking a phase changes the detail title', byId.get('dc-dtitle').textContent !== before);

if (fail.length) { process.stderr.write('FAIL: ' + fail.join('; ') + '\n'); process.exit(1); }
process.stdout.write('render_smoke: PASS (' + repos + ' repos, ' + rows.length + ' rows)\n');
