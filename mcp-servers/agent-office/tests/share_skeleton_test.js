'use strict';
// node tests/share_skeleton_test.js — shareSkeletons (cắt từ web/index.html) chạy với three.min.js thật.
// BUG-REV-AO-PERF-3: mỗi lưới có da của một người giữ một Skeleton riêng (cùng xương) -> ~300 lần tải texture xương mỗi khung.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const web = path.join(__dirname, '..', 'web');
const html = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
const m = html.match(/function shareSkeletons\(model\) \{[\s\S]*?\n\}\n/);
assert.ok(m, 'không tìm thấy shareSkeletons trong index.html');
assert.match(html, /model\.scale\.setScalar\(c\.scale\); root\.add\(model\);\n  shareSkeletons\(model\);/, 'spawnActor phải gọi shareSkeletons ngay sau khi nhân bản (trước khi tạo viền)');
const ctx = { console, self: {}, window: {} };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(web, 'vendor', 'three.min.js'), 'utf8'), ctx);
const THREE = ctx.THREE || ctx.self.THREE || ctx.window.THREE;
assert.ok(THREE && THREE.SkinnedMesh, 'không nạp được three.min.js');
ctx.THREE = THREE;
vm.runInContext(m[0] + '\nthis.shareSkeletons = shareSkeletons;', ctx);

const bones = [new THREE.Bone(), new THREE.Bone()]; bones[0].add(bones[1]);
const model = new THREE.Group(); model.add(bones[0]);
const geo = new THREE.BufferGeometry();
const mk = (inv) => { const s = new THREE.SkinnedMesh(geo, new THREE.MeshBasicMaterial()); model.add(s); s.bind(new THREE.Skeleton(bones, inv), new THREE.Matrix4()); return s; };
const a = mk(), b = mk(), c = mk();
const other = new THREE.Matrix4().makeTranslation(1, 0, 0);
const d = mk([new THREE.Matrix4(), other]); // boneInverses khác: giữ riêng
assert.notStrictEqual(a.skeleton, b.skeleton);
const n = ctx.shareSkeletons(model);
assert.strictEqual(n, 2, 'còn đúng 2 bộ xương (chung + cái có boneInverses khác), thấy ' + n);
assert.strictEqual(a.skeleton, b.skeleton); assert.strictEqual(b.skeleton, c.skeleton);
assert.notStrictEqual(d.skeleton, a.skeleton);
assert.ok(b.bindMatrixInverse.equals(new THREE.Matrix4().copy(b.bindMatrix).invert()));
console.log('share_skeleton_test OK');
