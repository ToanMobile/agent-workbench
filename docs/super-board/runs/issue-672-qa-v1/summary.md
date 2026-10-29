# QA #672 v1 (PR #682, head 32ca4fb3)

- `node --test tests/audited-head-merge.test.js` (mcp-servers/antigravity-pm-mcp): exit 0, 5/5 pass (MH1-MH5)
- `npm test`: exit 0, 329/329 pass; `npm run lint`: exit 0
- Đột biến: bỏ kiểm tra cây merge-tree thì MH4 (evil merge, -s ours) ĐỎ (pass 4, fail 1); khôi phục thì xanh
- Gate: post-fix-gate.py --run-tests --scoped --brief --json exit 0; super-board-qa-exit2.sh = pass
- origin/main đã nằm trong nhánh (merge: Already up to date)

| AC | Bằng chứng |
|---|---|
| 1. hai lệnh git | merge-head.js: diff --name-only auditedHead head -- file PR, và so bản ghi --raw với thay đổi của main (kèm kiểm cây merge-tree) |
| 2. merge hợp lệ được chấp nhận | MH1, MH5 |
| 3. thay đổi lạ bị từ chối | MH2, MH4 |
| 4. head không phải merge của auditedHead bị từ chối | MH3 |
| 5. notes ghi parent1, parent2, hai kết quả diff | MH1 |
