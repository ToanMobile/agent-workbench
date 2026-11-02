// #734 + review r19: sharedDaemon giu daemon java dung chung (ke ca JBR trong `Android Studio.app`, ten bundle co dau cach), KHONG giu lenh
// khac chi mang duong dan .app trong tham so, va quet argv dai khong backtrack bac hai (argv do lenh cua agent dat, quet dong bo tren event loop PM).
import test from 'node:test';
import assert from 'node:assert/strict';
import { sharedDaemon } from '../src/agentapi.js';

test('sharedDaemon: java daemon duoi <ten>.app/Contents (co dau cach) duoc giu; duong dan .app chi la THAM SO thi khong', () => {
  for (const argv of [
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java -Xmx2g org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.10',
    '/Applications/IntelliJ IDEA CE.app/Contents/jbr/Contents/Home/bin/java -cp x org.jetbrains.kotlin.daemon.KotlinCompileDaemon',
    '/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home/bin/java -cp x org.gradle.launcher.daemon.bootstrap.GradleDaemon',
    'java -cp x GradleDaemon',
  ]) assert.equal(sharedDaemon(argv), true, argv);
  for (const argv of [
    '/usr/local/bin/node -e x GradleDaemon',
    '/usr/local/bin/node -e x /x.app/Contents/java GradleDaemon',
    '/opt/homebrew/bin/python3 -c pass /tmp/z.app/Contents/bin/java x GradleDaemon',
  ]) assert.equal(sharedDaemon(argv), false, argv);
});

test('sharedDaemon: argv dai kieu `.app/Contents/` lap lai van xong nhanh (khong backtrack bac hai)', () => {
  for (const [name, argv] of [
    ['long nhau 240 KB', `/${'a.app/Contents/'.repeat(16000)}`],
    ['tham so 240 KB', `/usr/bin/node ${'/a.app/Contents/java '.repeat(12000)}`],
    ['java khong co daemon, 240 KB', `/${'a.app/Contents/'.repeat(40)}java ${'x '.repeat(120000)}`],
  ]) {
    const t0 = process.hrtime.bigint();
    sharedDaemon(argv);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    // ban sua quet ~0,1-3 ms; ban backtrack bac hai mat 1,8-8,8 s voi 240 KB (do r19) => tran 1 s du rong cho may tai cao
    assert.ok(ms < 1000, `${name}: ${ms.toFixed(1)} ms`);
  }
});
