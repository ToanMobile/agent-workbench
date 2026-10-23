'use strict';
// Chạy bằng node: node tests/present_pose_test.js. Chạy thật computePresent/applySit/startWalks-snapshot cắt từ web/index.html
// trên bộ xương giả: (6) Head không quay tích luỹ khi track Idle của Head hằng; (5) snapshot lưu faceOut.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'index.html'), 'utf8');
const ctx = { console };
ctx.window = ctx.self = ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'web', 'vendor', 'three.min.js'), 'utf8'), ctx);
const THREE = ctx.THREE;
assert.ok(THREE, 'three.min.js nạp được');

const grab = (re, what) => { const m = html.match(re); assert.ok(m, 'không tìm thấy ' + what + ' trong index.html'); return m[0]; };
const src = [
  grab(/const smooth01 = .*\n/, 'smooth01'),
  grab(/const bump = .*\n/, 'bump'),
  grab(/function computePresent\(root, idle\) \{[\s\S]*?\n\}\n/, 'computePresent'),
  grab(/const _sq = .*\n/, '_sq'),
  grab(/function applySit\(a, t\) \{[\s\S]*?\n\}\n/, 'applySit'),
  grab(/function snapshotPeople\(\) \{[\s\S]*?\n\}\n/, 'snapshotPeople'),
  grab(/const seatYaw = .*\n/, 'seatYaw'),
].join('\n') + '\nthis.computePresent = computePresent; this.applySit = applySit; this.snapshotPeople = snapshotPeople;';
ctx.deskAt = new Map(); ctx.walkers = []; ctx.DESK_YAW = 0;
vm.runInContext(src, ctx);

// Bộ xương: Hips → Spine → Head → HeadTop; hai tay. Idle chỉ có track hằng cho Head (vắng/hằng = mixer không ghi lại).
function skeleton() {
  const root = new THREE.Group(), mk = (name, parent, y) => { const b = new THREE.Bone(); b.name = name; b.position.set(0, y, 0); parent.add(b); return b; };
  const hips = mk('Hips', root, 1), spine = mk('Spine', hips, 0.3), head = mk('Head', spine, 0.4); mk('HeadTop', head, 0.2);
  for (const [sd, x] of [['R', -0.3], ['L', 0.3]]) {
    const ua = mk('UpperArm' + sd, spine, 0.3); ua.position.x = x; const la = mk('LowerArm' + sd, ua, 0.3); mk('Hand' + sd, la, 0.3);
  }
  root.updateMatrixWorld(true);
  return root;
}
const idle = new THREE.AnimationClip('Idle', 1, [new THREE.QuaternionKeyframeTrack('Head.quaternion', [0, 1], [0, 0, 0, 1, 0, 0, 0, 1])]);

{ // (6) 300 khung: quaternion Head bằng đúng một lần off*k, không cộng dồn
  const root = skeleton(), present = ctx.computePresent(root, idle);
  const a = { model: new THREE.Group(), present, presentW: 1, ph: 0, bm: new Map(), pose: { drop: 0, legs: [], feet: [], arms: [] }, sitW: 0, armW: 0 };
  root.traverse((o) => { if (o.isBone) a.bm.set(o.name, o); });
  const head = a.bm.get('Head'), seen = [];
  for (let f = 0; f < 300; f++) { ctx.applySit(a, 2 + f * 0.0001); seen.push(head.quaternion.clone()); } // t gần như đứng yên: k hầu như không đổi
  const angle = (q) => 2 * Math.acos(Math.min(1, Math.abs(q.w)));
  const maxAngle =Math.max(...seen.map(angle)), drift = seen[299].angleTo(seen[0]);
  assert.ok(maxAngle < 0.6, 'Head quay tích luỹ: góc lớn nhất ' + maxAngle.toFixed(3) + ' rad (một lần chỉ ~0.55)');
  assert.ok(drift < 0.01, 'Head trôi giữa khung 0 và 299: ' + drift.toFixed(4) + ' rad');
  a.presentW = 0; ctx.applySit(a, 1); // thôi thuyết trình: đầu về gốc
  assert.ok(head.quaternion.angleTo(new THREE.Quaternion()) < 1e-6, 'Head không về gốc khi presentW = 0');
}

{ // (5) snapshot lưu faceOut của chỗ ngồi
  const pg = { visible: true };
  ctx.deskAt.set('w1', { w: { id: 'w1' }, pg, pos: new THREE.Vector3(), sits: false, sc: 1, desk: null, faceOut: true, yaw: 0 });
  ctx.deskAt.set('w2', { w: { id: 'w2' }, pg, pos: new THREE.Vector3(), sits: true, sc: 1, desk: null, faceOut: false, yaw: 0 });
  const snap = ctx.snapshotPeople();
  assert.strictEqual(snap.byId.get('w1').faceOut, true, 'snapshot mất faceOut của người ở trạm');
  assert.strictEqual(snap.byId.get('w2').faceOut, false);
}
console.log('present_pose_test: ok');
