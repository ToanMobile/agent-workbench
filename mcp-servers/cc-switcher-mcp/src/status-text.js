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
    const pct = p.remainingPct ?? 100;
    const reset = p.resetTimeFormatted ? ` · ⏰ ${p.resetTimeFormatted} (${p.resetRemainHuman})` : '';
    const icon = p.isFrozen || pct <= 0 ? '🔴' : (p.isParallelActive ?? p.isActive) ? '🟢' : '⚪️';
    const repos = p.assignedRepoCount > 0 ? ` · ${p.assignedRepoCount} repo` : '';
    lines.push(`${icon} ${p.name}${repos}`);
    lines.push(`   ${bar(pct)} Còn ${pct}%${reset}`);
  }
  lines.push('');
  BACKUP_ORDER.map((id) => report.profiles.find((p) => p.id === id)).filter(Boolean).forEach((p, i) => {
    const icon = p.isFrozen ? '🔴' : p.isActive ? '🟢' : '⚪️';
    lines.push(`${icon} Dự phòng ${i + 1} · ${p.name}${p.isActive ? ' — đang dùng' : ''}`);
  });
  if (Array.isArray(report.repoAssignments) && report.repoAssignments.length > 0) {
    lines.push('');
    for (const acc of ['finos', 'finos_team']) {
      const names = report.repoAssignments.filter((r) => r.account === acc).map((r) => r.name);
      lines.push(`📂 ${acc}: ${names.join(', ') || '(không có)'}`);
    }
  }
  lines.push('');
  lines.push(`🎛 Bảng điều khiển: ${panelUrl()}`);
  return lines.join('\n');
}
