// Minimal stand-in for the Artifact "Dashboard" runtime so workflow-map.page.html also opens as a plain file.
// It implements only what the page uses: dash.data, dash.calc, dash.onData. Data comes from the
// <script id="checks-data" type="application/json"> block that collect_rows.py embeds.
(function () {
  const store = new Map();
  const listeners = [];
  const text = document.getElementById('checks-data').textContent;
  store.set('checks', JSON.parse(text));
  window.dash = {
    data(id) {
      return store.has(id) ? { status: 'ok', data: store.get(id) } : { status: 'missing', data: [] };
    },
    // calcs run once, in the order they are declared, over the rows of their inputs
    calc(id, spec) {
      store.set(id, spec.fn(...spec.inputs.map((i) => store.get(i))));
    },
    onData(fn) {
      listeners.push(fn);
      fn();
    },
  };
  window.addEventListener('resize', () => listeners.forEach((fn) => fn()));
})();
