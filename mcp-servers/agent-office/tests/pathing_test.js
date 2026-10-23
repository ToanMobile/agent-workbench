'use strict';
// Chạy bằng node: node tests/pathing_test.js. Thoát khác 0 nếu có ca sai.
const assert = require('assert');
const P = require('../web/pathing.js');

function wallWithDoor() { // tường dọc x=0 từ z=-10..10, cửa ở z∈[3,5]
  const g = P.createGrid(-10, -10, 10, 10, 0.5);
  P.blockRect(g, 0, -3.5, 0.1, 6.5, 0, 0.3); // z -10..3
  P.blockRect(g, 0, 7.5, 0.1, 2.5, 0, 0.3);  // z 5..10
  return g;
}
const crosses = (p, g) => { for (let k = 2; k < p.length; k += 2) if (!P.lineClear(g, p[k - 2], p[k - 1], p[k], p[k + 1])) return false; return true; };

{ // đi vòng qua cửa, mọi đoạn đều không vướng
  const g = wallWithDoor(), p = P.findPath(g, -6, -6, 6, -6);
  assert(p, 'có đường');
  assert(crosses(p, g), 'không đoạn nào xuyên tường');
  assert(p.some((v, k) => k % 2 === 0 && k > 0 && k < p.length - 2 && Math.abs(v) < 2) || P.pathLength(p) > 12 * 1.4, 'phải vòng qua cửa');
  assert(P.pathLength(p) < 40, 'không vòng quá xa');
}
{ // đường thẳng khi không vướng
  const g = P.createGrid(-10, -10, 10, 10, 0.5), p = P.findPath(g, -8, -8, 8, 8);
  assert.strictEqual(p.length, 4, 'kéo căng về một đoạn');
}
{ // đích kín hoàn toàn: không có đường
  const g = P.createGrid(-10, -10, 10, 10, 0.5);
  P.blockRect(g, 6, 6, 2, 2, 0, 0); P.blockRect(g, 0, 0, 0.1, 10, 0, 0.3); // tường kín cả bề dọc
  assert.strictEqual(P.findPath(g, -6, -6, 6, -6), null);
}
{ // đích nằm trong khung bàn: vẫn tới được, điểm cuối đúng đích
  const g = P.createGrid(-10, -10, 10, 10, 0.5);
  P.blockRect(g, 2, 2, 1.4, 0.8, 0.85, 0.35);
  const p = P.findPath(g, -6, -6, 2, 2);
  assert(p && p[p.length - 2] === 2 && p[p.length - 1] === 2);
}
{ // xoay hình chữ nhật đúng chiều của three (Y dương: +x quay về phía -z)
  const g = P.createGrid(-5, -5, 5, 5, 0.25);
  P.blockRect(g, 0, 0, 2, 0.1, Math.PI / 4, 0);
  assert(P.lineClear(g, 1, 1, 1.4, 1.4), 'góc +x,+z còn trống');
  assert(!P.lineClear(g, 1, -1, 1.2, -1.2), 'trục dài nằm ở +x,-z');
}
{ // tường chéo toàn ô chạm góc: không được chui qua kẽ góc
  const g = P.createGrid(0, 0, 10, 10, 1);
  for (let i = 0; i < 10; i++) g.blocked[i * 10 + i] = 1;
  assert.strictEqual(P.findPath(g, 8.5, 1.5, 1.5, 8.5), null);
}
{ // tường mỏng hơn một ô, nằm giữa hai tâm ô: vẫn phải chặn (lưới chặn mọi ô chạm vào vật cản)
  const g = P.createGrid(0, 0, 10, 10, 0.25);
  P.blockRect(g, 5.0, 5, 0.07, 6, 0, 0); // x = 5.0 nằm đúng mép giữa hai ô
  assert.strictEqual(P.findPath(g, 2, 5, 8, 5), null, 'không đi xuyên vách mỏng');
}
{ // hai phòng chung hành lang: đi từ phòng này sang phòng kia phải qua cả hai cửa, không đoạn nào xuyên tường
  const g = P.createGrid(-1, -1, 21, 14, 0.25), walls = [];
  const wall = (x, z, hw, hd) => { walls.push([x, z, hw, hd]); P.blockRect(g, x, z, hw, hd, 0, 0); };
  wall(10, 5, 0.07, 5);                 // vách giữa hai phòng, z 0..10
  wall(0, 5, 0.07, 5); wall(20, 5, 0.07, 5); wall(10, 0, 10, 0.07);
  wall(3.5, 10, 3.5, 0.07); wall(9.5, 10, 0.5, 0.07);   // tường trước phòng trái, cửa x 7..9
  wall(13.5, 10, 3.5, 0.07); wall(19.5, 10, 0.5, 0.07); // tường trước phòng phải, cửa x 17..19
  const p = P.findPath(g, 3, 4, 14, 4);
  assert(p, 'có đường qua hành lang');
  const g0 = P.createGrid(-1, -1, 21, 14, 0.25); walls.forEach(([x, z, hw, hd]) => P.blockRect(g0, x, z, hw, hd, 0, 0));
  for (let k = 2; k < p.length; k += 2) assert(P.lineClear(g0, p[k - 2], p[k - 1], p[k], p[k + 1]), 'đoạn ' + k / 2 + ' xuyên tường');
  const crossesAt = (x0, x1) => { for (let k = 2; k < p.length; k += 2) { const za = p[k - 1], zb = p[k + 1]; if ((za - 10) * (zb - 10) <= 0 && za !== zb) { const t = (10 - za) / (zb - za), x = p[k - 2] + (p[k] - p[k - 2]) * t; if (x > x0 && x < x1) return true; } } return false; };
  assert(crossesAt(7, 9), 'ra qua cửa phòng trái'); assert(crossesAt(17, 19), 'vào qua cửa phòng phải');
}
{ // mở chỗ ngồi sát vách không được đục thủng vách: planRoute chặn lại tường sau khi mở
  const walls = [{ x: 5, z: 5, hw: 0.03, hd: 5 }];
  const mk = () => { const g = P.createGrid(0, 0, 10, 10, 0.25); walls.forEach((w) => P.blockRect(g, w.x, w.z, w.hw, w.hd, 0, 0)); return g; };
  const p = P.planRoute([mk()], walls, 4.5, 5, 5.5, 5, 0.7); // ghế hai bên vách, cách vách 0,5
  assert.strictEqual(p, null, 'vách kín thì không có đường, không đục vách');
  const g0 = mk(); const q = P.planRoute([g0], walls, 4.5, 2, 4.5, 8, 0.7);
  assert(q && q[q.length - 2] === 4.5 && q[q.length - 1] === 8, 'cùng phía vách vẫn tới được');
  for (let k = 2; k < q.length; k += 2) assert(P.lineClear(mk(), q[k - 2], q[k - 1], q[k], q[k + 1]), 'đoạn không xuyên vách');
}
{ // hai chỗ sát hai bên một vách mỏng: đường kéo căng không được đi tắt xuyên vách (phải vòng qua cửa)
  const walls = [{ x: 5, z: 3, hw: 0.03, hd: 3 }, { x: 5, z: 8.5, hw: 0.03, hd: 1.5 }]; // vách x=5, cửa ở z 6..7
  const g = P.createGrid(0, 0, 10, 10, 0.25); walls.forEach((w) => P.blockRect(g, w.x, w.z, w.hw, w.hd, 0, 0));
  const noCross = (p) => { for (let k = 2; k < p.length; k += 2) {
    if ((p[k - 2] - 5) * (p[k] - 5) >= 0) continue; // đoạn không đi qua đường x = 5
    const zc = p[k - 1] + (p[k + 1] - p[k - 1]) * (5 - p[k - 2]) / (p[k] - p[k - 2]), crosses = zc < 6 || zc > 7; // chỉ được qua khe cửa z 6..7
    assert(!crosses, 'đoạn ' + k / 2 + ' đi tắt xuyên vách');
  } };
  const p = P.planRoute([g], walls, 4.8, 2, 5.2, 2, 0.7); // hai chỗ cách vách 0,2 (trong ô vách): có đường thì phải qua cửa, không thì null
  assert.strictEqual(p, null, 'ghế nằm trong ô vách: không có đường an toàn, người tới thẳng bàn mới');
  const q = P.planRoute([g], walls, 4.6, 2, 5.4, 2, 0.7); // cách vách 0,4: phải có đường, và đường đó vòng qua cửa
  assert(q, 'có đường qua cửa'); noCross(q);
}
{ // lưới chặt không có đường (lề rộng bịt khe) thì rơi sang lưới lỏng (chiều xoay của vách đã có ca riêng ở trên)
  const walls = [{ x: 5, z: 2.5, hw: 0.03, hd: 2.5, yaw: 0 }, { x: 5, z: 8, hw: 0.03, hd: 2, yaw: 0 }]; // khe vách x=5 ở z 5..6
  const mk = (m) => { const g = P.createGrid(0, 0, 10, 10, 0.25); walls.forEach((w) => P.blockRect(g, w.x, w.z, w.hw, w.hd, w.yaw, m)); return g; };
  const tight = mk(0.6), loose = mk(0);
  assert.strictEqual(P.planRoute([tight], walls, 2, 3, 8, 3, 0.7), null, 'lưới chặt: khe 1 m bị lề 0,6 bịt kín');
  const p = P.planRoute([tight, loose], walls, 2, 3, 8, 3, 0.7);
  assert(p, 'rơi sang lưới lỏng thì có đường');
  const g0 = mk(0); for (let k = 2; k < p.length; k += 2) assert(P.lineClear(g0, p[k - 2], p[k - 1], p[k], p[k + 1]), 'không xuyên vách');
}
{ // tốc độ: giảm êm khi gần đích, chạy hết cỡ khi xa
  assert.strictEqual(P.desiredSpeed(100, 3, 4, 0.3), 3);
  assert(P.desiredSpeed(0.5, 3, 4, 0.3) < 3 && P.desiredSpeed(0, 3, 4, 0.3) === 0.3);
}
{ // góc: đi đường ngắn qua ±π
  const a = P.dampAngle(3.0, -3.0, 5, 0.1);
  assert(a > 3.0 || a < -3.0 + 1e-9, 'quay qua π thay vì đảo ngược');
}
console.log('pathing ok');
