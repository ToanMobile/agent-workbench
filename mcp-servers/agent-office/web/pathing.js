// Tìm đường cho người đi trong văn phòng: lưới ô thô + A* + kéo căng đường (string pulling).
// Hàm thuần, không đụng DOM/three, chạy được cả trong trình duyệt (window.OfficePath) lẫn node (tests/pathing_test.js).
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.OfficePath = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  function createGrid(minX, minZ, maxX, maxZ, cell) {
    const nx = Math.max(1, Math.ceil((maxX - minX) / cell)), nz = Math.max(1, Math.ceil((maxZ - minZ) / cell));
    return { minX, minZ, cell, nx, nz, blocked: new Uint8Array(nx * nz) };
  }
  const cellX = (g, x) => Math.floor((x - g.minX) / g.cell);
  const cellZ = (g, z) => Math.floor((z - g.minZ) / g.cell);
  const inside = (g, i, j) => i >= 0 && j >= 0 && i < g.nx && j < g.nz;
  const isBlocked = (g, i, j) => !inside(g, i, j) || g.blocked[j * g.nx + i] === 1;

  // Chặn hình chữ nhật tâm (cx, cz), nửa cạnh hw x hd, xoay yaw quanh trục Y, nở thêm margin (bán kính người).
  function blockRect(g, cx, cz, hw, hd, yaw, margin) {
    // nở thêm nửa ô để chặn mọi ô chạm vào vật cản: vách mỏng hơn một ô nằm giữa hai tâm ô vẫn phải chặn
    const m = (margin || 0) + g.cell / 2, c = Math.cos(yaw || 0), s = Math.sin(yaw || 0);
    const R = Math.hypot(hw, hd) + m;
    const i0 = Math.max(0, cellX(g, cx - R)), i1 = Math.min(g.nx - 1, cellX(g, cx + R));
    const j0 = Math.max(0, cellZ(g, cz - R)), j1 = Math.min(g.nz - 1, cellZ(g, cz + R));
    for (let j = j0; j <= j1; j++) {
      for (let i = i0; i <= i1; i++) {
        const px = g.minX + (i + 0.5) * g.cell - cx, pz = g.minZ + (j + 0.5) * g.cell - cz;
        // đưa về hệ của hình chữ nhật (three: xoay Y dương đưa +x về phía -z)
        const lx = px * c - pz * s, lz = px * s + pz * c;
        if (Math.abs(lx) <= hw + m && Math.abs(lz) <= hd + m) g.blocked[j * g.nx + i] = 1;
      }
    }
  }
  // Mở lại vùng tròn quanh một điểm (chỗ ngồi nằm trong khung bàn).
  function clearCircle(g, cx, cz, r) {
    const i0 = Math.max(0, cellX(g, cx - r)), i1 = Math.min(g.nx - 1, cellX(g, cx + r));
    const j0 = Math.max(0, cellZ(g, cz - r)), j1 = Math.min(g.nz - 1, cellZ(g, cz + r));
    for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) {
      const px = g.minX + (i + 0.5) * g.cell - cx, pz = g.minZ + (j + 0.5) * g.cell - cz;
      if (px * px + pz * pz <= r * r) g.blocked[j * g.nx + i] = 0;
    }
  }

  // Đường thẳng đi qua toàn ô trống? Lấy mẫu mỗi nửa ô.
  // skipA, skipB: chỉ số hai ô được bỏ qua (ô của chỗ đầu/đích nằm trong khung bàn), mọi ô khác phải trống
  function lineClear(g, ax, az, bx, bz, skipA, skipB) {
    const d = Math.hypot(bx - ax, bz - az), n = Math.max(1, Math.ceil(d / (g.cell * 0.5)));
    for (let k = 0; k <= n; k++) {
      const t = k / n, i = cellX(g, ax + (bx - ax) * t), j = cellZ(g, az + (bz - az) * t), c = j * g.nx + i;
      if (isBlocked(g, i, j) && c !== skipA && c !== skipB) return false;
    }
    return true;
  }

  // Ô trống gần nhất (vòng xoáy theo bán kính), null nếu hết lưới.
  function nearestFree(g, x, z) {
    const ci = cellX(g, x), cj = cellZ(g, z);
    if (!isBlocked(g, ci, cj)) return [ci, cj];
    const maxR = Math.max(g.nx, g.nz);
    for (let r = 1; r < maxR; r++) {
      let best = null, bd = Infinity;
      for (let dj = -r; dj <= r; dj++) for (let di = -r; di <= r; di++) {
        if (Math.max(Math.abs(di), Math.abs(dj)) !== r) continue;
        const i = ci + di, j = cj + dj;
        if (isBlocked(g, i, j)) continue;
        const d = di * di + dj * dj;
        if (d < bd) { bd = d; best = [i, j]; }
      }
      if (best) return best;
    }
    return null;
  }

  // Heap nhị phân nhỏ theo khoá f.
  function Heap() { this.k = []; this.v = []; }
  Heap.prototype.push = function (key, val) {
    const k = this.k, v = this.v; let i = k.length; k.push(key); v.push(val);
    while (i > 0) { const p = (i - 1) >> 1; if (k[p] <= key) break; k[i] = k[p]; v[i] = v[p]; i = p; }
    k[i] = key; v[i] = val;
  };
  Heap.prototype.pop = function () {
    const k = this.k, v = this.v, top = v[0], lk = k.pop(), lv = v.pop(), n = k.length;
    if (n) {
      let i = 0;
      for (;;) {
        let c = 2 * i + 1; if (c >= n) break;
        if (c + 1 < n && k[c + 1] < k[c]) c++;
        if (k[c] >= lk) break;
        k[i] = k[c]; v[i] = v[c]; i = c;
      }
      k[i] = lk; v[i] = lv;
    }
    return top;
  };

  const SQ2 = Math.SQRT2;
  // Trả về mảng điểm phẳng [x0, z0, x1, z1, ...] gồm đúng điểm đầu và đích, hoặc null nếu không có đường.
  function findPath(g, sx, sz, gx, gz) {
    const s = nearestFree(g, sx, sz), t = nearestFree(g, gx, gz);
    if (!s || !t) return null;
    const N = g.nx * g.nz, gs = new Float32Array(N).fill(Infinity), from = new Int32Array(N).fill(-1), done = new Uint8Array(N);
    const si = s[1] * g.nx + s[0], ti = t[1] * g.nx + t[0];
    const hf = (i, j) => { const dx = Math.abs(i - t[0]), dz = Math.abs(j - t[1]); return (dx + dz) + (SQ2 - 2) * Math.min(dx, dz); };
    const open = new Heap(); gs[si] = 0; open.push(hf(s[0], s[1]), si);
    let found = false;
    while (open.k.length) {
      const cur = open.pop();
      if (done[cur]) continue; done[cur] = 1;
      if (cur === ti) { found = true; break; }
      const ci = cur % g.nx, cj = (cur / g.nx) | 0;
      for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
        if (!di && !dj) continue;
        const i = ci + di, j = cj + dj;
        if (isBlocked(g, i, j)) continue;
        if (di && dj && (isBlocked(g, ci + di, cj) || isBlocked(g, ci, cj + dj))) continue; // không cắt góc
        const ni = j * g.nx + i; if (done[ni]) continue;
        const ng = gs[cur] + (di && dj ? SQ2 : 1);
        if (ng < gs[ni]) { gs[ni] = ng; from[ni] = cur; open.push(ng + hf(i, j), ni); }
      }
    }
    if (!found) return null;
    const cells = [];
    for (let c = ti; c !== -1; c = from[c]) cells.push(c);
    cells.reverse();
    const pts = [sx, sz];
    for (let k = 1; k < cells.length - 1; k++) pts.push(g.minX + ((cells[k] % g.nx) + 0.5) * g.cell, g.minZ + (((cells[k] / g.nx) | 0) + 0.5) * g.cell);
    pts.push(gx, gz);
    return pull(g, pts);
  }

  // Kéo căng: bỏ mọi điểm giữa nếu nhìn thẳng từ điểm trước tới điểm sau không vướng. Đầu/đích có thể nằm trong ô chặn
  // (chỗ ngồi), nên riêng hai ô đó được bỏ qua khi kiểm.
  function pull(g, p) {
    const out = [p[0], p[1]]; let a = 0; const n = p.length / 2;
    const e0 = cellZ(g, p[1]) * g.nx + cellX(g, p[0]), e1 = cellZ(g, p[2 * n - 1]) * g.nx + cellX(g, p[2 * n - 2]);
    while (a < n - 1) {
      let b = n - 1;
      while (b > a + 1) {
        if (lineClear(g, p[2 * a], p[2 * a + 1], p[2 * b], p[2 * b + 1], a === 0 ? e0 : -1, b === n - 1 ? e1 : -1)) break; // chỉ bỏ qua ô đầu/đích ở đoạn chạm chúng
        b--;
      }
      out.push(p[2 * b], p[2 * b + 1]); a = b;
    }
    return out;
  }

  // Lập đường giữa hai chỗ ngồi: thử lần lượt các lưới (chặt rồi lỏng) trên bản sao, mở vòng tròn quanh điểm đầu/đích
  // (chỗ ngồi nằm trong khung bàn). null khi không có đường nào: người gọi cho người tới thẳng, không đi xuyên tường.
  // mảng vách -> lưới chỉ có vách. Giả định: người gọi tạo mảng vách mới mỗi lần dựng cảnh, không thêm vách sau lần gọi đầu,
  // và luôn đưa kèm các lưới cùng khung (index.html: navWalls dựng lại cùng navTight/navLoose trong buildNav)
  const wallGrids = new WeakMap();
  function planRoute(grids, walls, sx, sz, gx, gz, clearR) {
    let wg = null; // lưới chỉ có vách (dựng một lần cho mỗi mảng vách): kiểm từng đoạn sau khi kéo căng
    const crossesWall = (p) => {
      if (!walls || !walls.length) return false;
      if (!wg) wg = wallGrids.get(walls);
      if (!wg) { const b = grids.find(Boolean); wg = createGrid(b.minX, b.minZ, b.minX + b.nx * b.cell, b.minZ + b.nz * b.cell, b.cell); for (const w of walls) blockRect(wg, w.x, w.z, w.hw, w.hd, w.yaw || 0, 0); wallGrids.set(walls, wg); }
      for (let k = 2; k < p.length; k += 2) if (!lineClear(wg, p[k - 2], p[k - 1], p[k], p[k + 1])) return true;
      return false;
    };
    for (const base of grids) {
      if (!base) continue;
      const g = Object.assign({}, base, { blocked: base.blocked.slice() });
      clearCircle(g, sx, sz, clearR); clearCircle(g, gx, gz, clearR);
      for (const w of walls || []) blockRect(g, w.x, w.z, w.hw, w.hd, w.yaw || 0, 0); // vòng mở không được đục thủng vách
      const p = findPath(g, sx, sz, gx, gz);
      if (p && !crossesWall(p)) return p;
    }
    return null;
  }

  function pathLength(p) { let d = 0; for (let k = 2; k < p.length; k += 2) d += Math.hypot(p[k] - p[k - 2], p[k + 1] - p[k - 1]); return d; }

  // Tốc độ mong muốn: chạy vmax, giảm êm khi còn gần đích (v = sqrt(2·a·còn lại)), không dưới vmin để khỏi bò.
  function desiredSpeed(remaining, vmax, accel, vmin) { return Math.max(vmin || 0, Math.min(vmax, Math.sqrt(2 * accel * Math.max(0, remaining)))); }
  // Góc tiến dần về đích theo hàm mũ, đi đường ngắn nhất qua ±π.
  function dampAngle(cur, target, rate, dt) {
    let d = target - cur; d = Math.atan2(Math.sin(d), Math.cos(d));
    return cur + d * (1 - Math.exp(-rate * dt));
  }

  return { createGrid, blockRect, clearCircle, lineClear, nearestFree, findPath, planRoute, pathLength, desiredSpeed, dampAngle };
});
