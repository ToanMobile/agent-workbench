// Khoi tao MCP Server (stdio) cho cc-switcher-mcp.
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { TOOLS, TOOLS_BY_NAME } from './tools.js';
import { logStructured, maskSecret } from './errors.js';

export const SERVER_NAME = 'cc-switcher-mcp';
export const SERVER_VERSION = '0.1.0';

const INSTRUCTIONS = `Quan ly va tu dong xoay vong an toan 6 profile CC Switch (3 Claude Code + 2 Antigravity Gemini + 1 Grok CLI) kem canh bao & dieu khien tu xa qua Telegram.
Quy tac chong ban:
- Khi tai khoan Claude dinh 429 / het quota, goi switcher_report_limit hoac switcher_rotate(markCurrentLimited=true) de dong bang tai khoan do 5 gio va chuyen sang profile an toan tiep theo.
- Cooldown an toan mac dinh giua 2 tai khoan Claude la 15 phut (900s); chuyen sang Antigravity hoac Grok thi khong can cho.`;

export function createServer() {
  const server = new Server(
    { name: SERVER_NAME, version: SERVER_VERSION },
    { capabilities: { tools: {} }, instructions: INSTRUCTIONS },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS.map((t) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const tool = TOOLS_BY_NAME.get(req.params.name);
    if (!tool) {
      return {
        content: [{ type: 'text', text: `Khong ton tai tool "${req.params.name}"` }],
        isError: true,
      };
    }
    try {
      const out = await tool.handler(req.params.arguments || {});
      const payload = typeof out === 'string' ? { text: out } : out;
      return {
        content: [{ type: 'text', text: maskSecret(payload.text ?? '') }],
        isError: Boolean(payload.isError),
      };
    } catch (err) {
      const hint = err?.hint ? `\nGợi ý: ${err.hint}` : '';
      logStructured('error', 'mcp_tool_error', {
        tool: req.params.name,
        code: err?.code || 'ERR',
        message: maskSecret(err?.message || String(err)),
      });
      return {
        content: [{ type: 'text', text: `${maskSecret(err?.message || String(err))}${hint}` }],
        isError: true,
      };
    }
  });

  return server;
}

export async function main() {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  logStructured('info', 'mcp_server_ready', {
    server: SERVER_NAME,
    version: SERVER_VERSION,
    toolCount: TOOLS.length,
  });
}
