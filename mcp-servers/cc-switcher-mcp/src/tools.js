// Dinh nghia 6 MCP tools cho cc-switcher-mcp: kiem tra trang thai, chuyen profile an toan, xoay vong va cau hinh Telegram.
import {
  getStatusReport,
  switchProfile,
  rotateNextProfile,
  reportRateLimit,
  updateAntiBanPolicy,
} from './profiles.js';
import {
  loadTelegramConfig,
  saveTelegramConfig,
  discoverChatId,
  sendTelegramNotification,
  formatStatusForTelegram,
  maskSecret,
} from './telegram.js';

export const TOOLS = [
  {
    name: 'switcher_status',
    description: 'Xem trang thai 6 profile CC Switch, tai khoan dang active, thoi gian Cooldown chong ban, thong ke token/chi phi va cau hinh Telegram.',
    inputSchema: {
      type: 'object',
      properties: {
        stateDir: {
          type: 'string',
          description: 'Thu muc trang thai CC Switch (mac dinh ~/.cc-switch).',
        },
      },
      additionalProperties: false,
    },
    async handler(args = {}) {
      const report = getStatusReport({ stateDir: args.stateDir });
      const tg = loadTelegramConfig(args.stateDir);
      const summary = formatStatusForTelegram(report);
      const tgInfo = `\n🔐 Telegram Bot: ${tg.botToken ? 'Đã cấu hình (' + maskSecret(tg.botToken, [tg.botToken]) + ')' : 'Chưa cấu hình'} | Chat ID: ${tg.chatId || 'Chưa có'}`;
      return {
        text: `${summary}${tgInfo}`,
      };
    },
  },
  {
    name: 'switcher_switch',
    description: 'Chuyen sang mot profile cu the (1..6 hoac id: finos, finos_team, max, antigravity, antigravity_pro, grok) kem kiem tra Anti-Ban Cooldown va gui thong bao Telegram.',
    inputSchema: {
      type: 'object',
      properties: {
        target: {
          type: ['string', 'number'],
          description: 'So thu tu profile (1..6) hoac ID profile (finos, finos_team, max, antigravity, antigravity_pro, grok).',
        },
        enforceCooldown: {
          type: 'boolean',
          description: 'Bat kiem tra Cooldown 15 phut giua 2 tai khoan Claude (mac dinh: true).',
        },
        notifyTelegram: {
          type: 'boolean',
          description: 'Gui tin nhan thong bao ve Telegram khi chuyen xong (mac dinh: true).',
        },
        stateDir: {
          type: 'string',
        },
      },
      required: ['target'],
      additionalProperties: false,
    },
    async handler(args = {}) {
      const res = switchProfile({
        stateDir: args.stateDir,
        target: args.target,
        enforceCooldown: args.enforceCooldown !== false,
        reason: 'mcp_tool_switch',
      });
      const msg = [
        '✅ ĐÃ CHUYỂN PROFILE AN TOÀN',
        `• Từ: ${res.previousProfile.name}`,
        `• Sang: ${res.activeProfile.name}`,
        `• Biến môi trường bảo vệ: ${JSON.stringify(res.env)}`,
      ].join('\n');
      if (args.notifyTelegram !== false) {
        await sendTelegramNotification(msg, { stateDir: args.stateDir });
      }
      return { text: msg };
    },
  },
  {
    name: 'switcher_rotate',
    description: 'Tu dong xoay sang profile an toan ke tiep trong 6 profile (bo qua tai khoan dang dong bang 5h hoac dang vung cooldown Claude).',
    inputSchema: {
      type: 'object',
      properties: {
        markCurrentLimited: {
          type: 'boolean',
          description: 'Danh dau profile hien tai vua het token/dinh 429 de dong bang 5h (mac dinh: false).',
        },
        notifyTelegram: {
          type: 'boolean',
          description: 'Gui thong bao Telegram sau khi xoay vong (mac dinh: true).',
        },
        stateDir: {
          type: 'string',
        },
      },
      additionalProperties: false,
    },
    async handler(args = {}) {
      const res = rotateNextProfile({
        stateDir: args.stateDir,
        markCurrentLimited: Boolean(args.markCurrentLimited),
        reason: args.markCurrentLimited ? 'mcp_rotate_on_limit' : 'mcp_rotate',
      });
      const msg = [
        '🔄 ĐÃ XOAY VÒNG PROFILE TỰ ĐỘNG',
        `• Từ: ${res.previousProfile.name}`,
        `• Sang: ${res.activeProfile.name}`,
        res.requiredWaitSec > 0
          ? `⏳ Khuyến nghị nghỉ an toàn: ${res.requiredWaitSec}s trước khi gọi tiếp.`
          : '🛡 Trạng thái: An toàn tuyệt đối (0 nguy cơ ban).',
      ].join('\n');
      if (args.notifyTelegram !== false) {
        await sendTelegramNotification(msg, { stateDir: args.stateDir });
      }
      return { text: msg };
    },
  },
  {
    name: 'switcher_report_limit',
    description: 'Bao cao tai khoan hien tai cham Rate Limit 429 / het token: Dong bang 5 gio, xoay sang tai khoan tiep theo va ban canh bao Telegram.',
    inputSchema: {
      type: 'object',
      properties: {
        reason: {
          type: 'string',
          description: 'Ly do cham limit (vi du: 429 Too Many Requests).',
        },
        autoSwitchNext: {
          type: 'boolean',
          description: 'Tu dong chuyen sang profile ke tiep (mac dinh: true).',
        },
        stateDir: {
          type: 'string',
        },
      },
      additionalProperties: false,
    },
    async handler(args = {}) {
      if (args.autoSwitchNext !== false) {
        const rotated = rotateNextProfile({
          stateDir: args.stateDir,
          markCurrentLimited: true,
          reason: args.reason || '429_rate_limit',
        });
        const msg = [
          '🚨 BÁO ĐỘNG 429 — ĐÃ ĐÓNG BĂNG 5 GIỜ & CHUYỂN TÀI KHOẢN',
          `❄️ Đã đóng băng: ${rotated.previousProfile.name}`,
          `▶️ Đang dùng: ${rotated.activeProfile.name}`,
          rotated.requiredWaitSec > 0
            ? `⏳ Thời gian nghỉ chống ban khuyến nghị: ${Math.ceil(rotated.requiredWaitSec / 60)} phút`
            : '✅ Đã chuyển sang hạ tầng an toàn.',
        ].join('\n');
        await sendTelegramNotification(msg, { stateDir: args.stateDir });
        return { text: msg };
      }

      const rep = reportRateLimit({
        stateDir: args.stateDir,
        reason: args.reason || '429_rate_limit',
      });
      return {
        text: `Đã đóng băng "${rep.limitedProfile.name}" trong ${rep.freezeMinutes} phút (đến ${rep.frozenUntilIso}). Gợi ý tiếp theo: ${rep.nextProfile?.name || 'N/A'}.`,
      };
    },
  },
  {
    name: 'switcher_configure_policy',
    description: 'Cau hinh thoi gian nghi chong ban (claudeCooldownMinutes mac dinh 15 phut, rateLimitFreezeMinutes mac dinh 300 phut = 5h).',
    inputSchema: {
      type: 'object',
      properties: {
        claudeCooldownMinutes: {
          type: 'number',
          description: 'So phut nghi giua 2 tai khoan Claude (khuyen nghi 10 - 15 phut).',
        },
        rateLimitFreezeMinutes: {
          type: 'number',
          description: 'So phut dong bang tai khoan vua dinh 429 (mac dinh 300 phut = 5 gio).',
        },
        stateDir: {
          type: 'string',
        },
      },
      additionalProperties: false,
    },
    async handler(args = {}) {
      const partial = {};
      if (typeof args.claudeCooldownMinutes === 'number') {
        partial.claudeSwitchCooldownSec = Math.round(args.claudeCooldownMinutes * 60);
      }
      if (typeof args.rateLimitFreezeMinutes === 'number') {
        partial.rateLimitFreezeSec = Math.round(args.rateLimitFreezeMinutes * 60);
      }
      const policy = updateAntiBanPolicy(args.stateDir, partial);
      return {
        text: `🛡 Đã cập nhật chính sách Anti-Ban:\n• Nghỉ giữa 2 tài khoản Claude: ${Math.round(policy.claudeSwitchCooldownSec / 60)} phút (${policy.claudeSwitchCooldownSec}s)\n• Đóng băng khi chạm 429: ${Math.round(policy.rateLimitFreezeSec / 60)} phút (${policy.rateLimitFreezeSec}s)`,
      };
    },
  },
  {
    name: 'switcher_telegram_setup',
    description: 'Luu Bot Token va Chat ID Telegram vao ~/.cc-switch/telegram.env (quyen 0600, ngoai Git), tu dong do Chat ID va gui tin nhan kiem tra.',
    inputSchema: {
      type: 'object',
      properties: {
        botToken: {
          type: 'string',
          description: 'Token Bot Telegram tu @BotFather.',
        },
        chatId: {
          type: 'string',
          description: 'Chat ID nguoi nhan (neu bo trong se tu dong do tu tin nhan /start gan nhat).',
        },
        sendTest: {
          type: 'boolean',
          description: 'Gui tin nhan test sau khi luu (mac dinh: true).',
        },
        stateDir: {
          type: 'string',
        },
      },
      additionalProperties: false,
    },
    async handler(args = {}) {
      let chatId = args.chatId;
      if (!chatId && args.botToken && args.sendTest !== false) {
        try {
          chatId = await discoverChatId(args.botToken);
        } catch {
          // Neu token chua hop le hoac chua co tin nhan /start thi giu nguyen chatId trong
        }
      }
      const saved = saveTelegramConfig(args.stateDir, {
        botToken: args.botToken,
        chatId,
      });
      let testStatus = 'Chưa gửi tin nhắn thử.';
      if (args.sendTest !== false && saved.chatId) {
        const res = await sendTelegramNotification(
          '✅ CC Switcher MCP đã kết nối thành công! Gõ /status để điều khiển 6 tài khoản từ điện thoại.',
          { stateDir: args.stateDir },
        );
        testStatus = res.sent ? 'Đã gửi tin nhắn test thành công!' : `Không gửi được tin nhắn test: ${res.reason}`;
      }
      return {
        text: [
          '🔐 ĐÃ LƯU CẤU HÌNH TELEGRAM AN TOÀN (Quyền 0600)',
          `• File: ${saved.envFile}`,
          `• Token: ${saved.botTokenMasked}`,
          `• Chat ID: ${saved.chatId || '(Chưa có — hãy nhắn /start vào Bot rồi gọi lại tool này)'}`,
          `• Trạng thái: ${testStatus}`,
        ].join('\n'),
      };
    },
  },
];

export const TOOLS_BY_NAME = new Map(TOOLS.map((t) => [t.name, t]));
