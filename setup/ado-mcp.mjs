// Azure DevOps MCP launcher (Claude Code, Codex, Copilot, Antigravity; Windows + WSL).
// Template from BCALInsights/setup — copy it into your MCP_PAT folder next to DevOpsPAT.txt (see SETUP.md).
// Reads the raw PAT from DevOpsPAT.txt next to this script, encodes it as base64(":PAT") and starts
// @azure-devops/mcp for org essencebs. Extra args are passed through (e.g. `-d core work-items`).
// PAT rotation: overwrite DevOpsPAT.txt and restart the session (or reconnect the server via /mcp).
import { existsSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { setDefaultResultOrder } from 'node:dns';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const patFile = join(dirname(fileURLToPath(import.meta.url)), 'DevOpsPAT.txt');
const pat = existsSync(patFile) ? readFileSync(patFile, 'utf8').trim() : '';
if (!pat) throw new Error(`Azure DevOps PAT file ${patFile} is missing or empty.`);
process.env.PERSONAL_ACCESS_TOKEN = Buffer.from(':' + pat).toString('base64');

const win = process.platform === 'win32';
const mcpArgs = ['essencebs', '--authentication', 'pat', ...process.argv.slice(2)];
// Global npm install (mcp-setup.md, step 1): Windows %APPDATA%\npm, WSL/Linux <node prefix>/lib.
const globalRoot = win
  ? join(process.env.APPDATA ?? '', 'npm', 'node_modules')
  : join(dirname(process.execPath), '..', 'lib', 'node_modules');
const entry = join(globalRoot, '@azure-devops', 'mcp', 'dist', 'index.js');

if (existsSync(entry)) {
  // In-process: starts in < 1 s and leaves no orphaned child when the client kills this process.
  setDefaultResultOrder('ipv4first'); // corp network resets IPv6 connections to aex.dev.azure.com
  process.argv = [process.execPath, entry, ...mcpArgs];
  await import(pathToFileURL(entry).href);
} else {
  // No global install: npx fallback (slower start, can hit the client's 30 s handshake timeout).
  const env = {
    ...process.env,
    NODE_OPTIONS: [process.env.NODE_OPTIONS, '--dns-result-order=ipv4first'].filter(Boolean).join(' '),
  };
  const npx = win ? 'npx' : join(dirname(process.execPath), 'npx');
  const child = spawn(npx, ['-y', '@azure-devops/mcp', ...mcpArgs], { stdio: 'inherit', env, shell: win });
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => child.kill(sig));
  child.on('exit', (code, signal) => (signal ? process.kill(process.pid, signal) : process.exit(code ?? 1)));
}
