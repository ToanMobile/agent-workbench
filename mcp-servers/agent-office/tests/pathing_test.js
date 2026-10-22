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
{ // tốc độ: giảm êm khi gần đích, chạy hết cỡ khi xa
  assert.strictEqual(P.desiredSpeed(100, 3, 4, 0.3), 3);
  assert(P.desiredSpeed(0.5, 3, 4, 0.3) < 3 && P.desiredSpeed(0, 3, 4, 0.3) === 0.3);
}
{ // góc: đi đường ngắn qua ±π
  const a = P.dampAngle(3.0, -3.0, 5, 0.1);
  assert(a > 3.0 || a < -3.0 + 1e-9, 'quay qua π thay vì đảo ngược');
}
console.log('pathing ok');
