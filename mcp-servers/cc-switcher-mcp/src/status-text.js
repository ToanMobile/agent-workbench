// Ban tom tat trang thai dang van ban cho MCP tool switcher_status va CLI --status (khong phai bang dieu khien Telegram).
import { panelUrl, BACKUP_ORDER } from './panel.js';

function bar(pct) {
  const v = Math.max(0, Math.min(100, Number(pct) || 0));
  const filled = Math.round(v / 10);
  return `[${'█'.repeat(filled)}${'░'.repeat(10 - filled)}]`;
}

export function formatStatusText(report) {
  const cdMin = Math.round((report.policy?.claudeSwitchCooldownSec ?? 900) / 60);
  const lines = [];
  const a = report.activeProfile;
  lines.push('CC Switcher · trạng thái');
  lines.push(`▶️ Đang dùng: ${a.shortLabel || a.name} (Còn ${a.remainingPct ?? 100}%${a.resetTimeFormatted ? ` · ⏰ ${a.resetTimeFormatted}` : ''})`);
  lines.push(report.claudeCooldownRemainSec > 0
    ? `🛡 Anti-Ban: chờ ${report.claudeCooldownRemainSec}s trước khi đổi tài khoản Claude · nghỉ ${cdMin}p`
    : `🛡 Anti-Ban: đổi ngay được · nghỉ ${cdMin}p`);
  lines.push(`💰 Chi phí: $${report.usage.totalCostUsd} (${report.usage.totalRequests} req)`);
  lines.push('');
  for (const p of report.profiles.filter((x) => x.vendor === 'anthropic')) {
    const stale = p.remainingPct === null;
    const pct = p.remainingPct ?? 100;
    const reset = p.resetTimeFormatted ? ` · ⏰ ${p.resetTimeFormatted} (${p.resetRemainHuman})` : '';
    const weekly = p.weeklyRemainingPct != null
      ? ` · tuần còn ${p.weeklyRemainingPct}%${p.weeklyResetFormatted ? ` (reset ${p.weeklyResetFormatted})` : ''}`
      : '';
    const icon = stale ? '⚠️' : p.isFrozen || pct <= 0 ? '🔴' : (p.isParallelActive ?? p.isActive) ? '🟢' : '⚪️';
    const repos = p.assignedRepoCount > 0 ? ` · ${p.assignedRepoCount} repo` : '';
    lines.push(`${icon} ${p.name}${repos}`);
    lines.push(stale ? '   Số liệu cũ, không làm mới được (đăng nhập lại)' : `   ${bar(pct)} Còn ${pct}%${reset}${weekly}`);
  }
  lines.push('');
  BACKUP_ORDER.map((id) => report.profiles.find((p) => p.id === id)).filter(Boolean).forEach((p, i) => {
    const icon = p.isFrozen ? '🔴' : p.isActive ? '🟢' : '⚪️';
    lines.push(`${icon} Dự phòng ${i + 1} · ${p.name}${p.isActive ? ' — đang dùng' : ''}`);
  });
  if (Array.isArray(report.repoAssignments) && report.repoAssignments.length > 0) {
    lines.push('');
    const accs = ['finos_toan', 'finos_linh'];
    for (const r of report.repoAssignments) if (r.account && !accs.includes(r.account)) accs.push(r.account);
    for (const acc of accs) {
      const names = report.repoAssignments.filter((r) => r.account === acc).map((r) => r.name);
      lines.push(`📂 ${acc}: ${names.join(', ') || '(không có)'}`);
    }
    const loose = report.repoAssignments.filter((r) => !r.account).map((r) => r.name);
    if (loose.length) lines.push(`📂 chưa ghim (~/.claude): ${loose.join(', ')}`);
  }
  lines.push('');
  lines.push(`🎛 Bảng điều khiển: ${panelUrl()}`);
  return lines.join('\n');
}
