// Ban tom tat trang thai dang van ban cho MCP tool switcher_status va CLI --status (khong phai bang dieu khien Telegram).
import { panelUrl, BACKUP_ORDER } from './panel.js';

/** Cau bao dung ly do khong lay duoc quota; refresh token con thi KHONG can dang nhap lai. */
export function quotaIssueText(reason, mismatch, idle = false) {
  if (reason === 'wrong_account') return `Sai tài khoản: thư mục đang đăng nhập ${mismatch?.actual || '?'}, cần ${mismatch?.expected || '?'} — bấm "Đăng nhập lại" trên trang cc-switcher`;
  if (reason === 'token_expired' && idle) return 'Chưa dùng gần đây nên token đã hết hạn (bình thường). Mở claude với thư mục này hoặc bấm "Đăng nhập lại" khi muốn chuyển sang tài khoản này';
  if (reason === 'token_expired') return 'Token hết hạn — bấm "Đăng nhập lại" trên trang cc-switcher (hoặc chạy claude auth login với thư mục này)';
  if (reason === 'throttled') return 'Endpoint quota đang giới hạn (429), sẽ thử lại sau';
  if (reason === 'network') return 'Lỗi mạng khi lấy quota, sẽ thử lại sau';
  if (reason === 'no_credentials') return 'Chưa có thông tin đăng nhập trong Keychain — bấm "Đăng nhập lại" trên trang cc-switcher';
  return 'Số liệu cũ, chưa làm mới được';
}

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
    lines.push(stale ? `   ${quotaIssueText(p.quotaIssue, p.accountMismatch, !(p.isParallelActive ?? p.isActive))}` : `   ${bar(pct)} Còn ${pct}%${reset}${weekly}`);
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
