#!/usr/bin/env bun
// in-html Mode 2 feedback server — foreground-blocking, plannotator-style.
//
// Serves one HTML file at GET / and accepts exactly one POST /submit.
// On submit: writes the JSON body to --answer, prints it to stdout, exits 0.
// All status banners go to stderr so stdout is clean for the agent to capture.
// Opens the browser by default. Prefers Chromium "--app=" mode (no tab chrome,
// window.close() works after submit). Falls back to xdg-open / open.
//
// Usage:
//   bun ~/.claude/skills/in-html/feedback-server.ts \
//     --file /tmp/in-html/<topic>.html \
//     --answer /tmp/in-html/answers/<turn-id>.json \
//     [--no-open] [--port 0] [--timeout 540]
//
// stdout (on success): single line of compact JSON — the submission.
// stderr: URL banner, answer-path banner, opener choice, timeout warnings.
// exit codes: 0 on submit, 1 on timeout, 2 on argv/file error.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const argv = Bun.argv.slice(2);
const opt = { file: "", answer: "", port: 0, timeoutSec: 540, open: true };

for (let i = 0; i < argv.length; i++) {
  const k = argv[i];
  const v = argv[i + 1];
  if (k === "--file") { opt.file = v; i++; }
  else if (k === "--answer") { opt.answer = v; i++; }
  else if (k === "--port") { opt.port = parseInt(v, 10); i++; }
  else if (k === "--timeout") { opt.timeoutSec = parseInt(v, 10); i++; }
  else if (k === "--open") { opt.open = true; }
  else if (k === "--no-open") { opt.open = false; }
}

if (!opt.file || !opt.answer) {
  console.error("error: --file and --answer are required");
  process.exit(2);
}
if (!existsSync(opt.file)) {
  console.error(`error: file not found: ${opt.file}`);
  process.exit(2);
}

mkdirSync(dirname(opt.answer), { recursive: true });

const html = readFileSync(opt.file, "utf8");

const server = Bun.serve({
  port: Number.isFinite(opt.port) ? opt.port : 0,
  async fetch(req) {
    const url = new URL(req.url);

    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      return new Response(html, {
        headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
      });
    }

    if (req.method === "POST" && url.pathname === "/submit") {
      const body = await req.text();
      try { JSON.parse(body); } catch (e) {
        return Response.json({ ok: false, error: `invalid JSON: ${e}` }, { status: 400 });
      }
      writeFileSync(opt.answer, body, "utf8");
      process.stdout.write(body.replace(/\s+$/, "") + "\n");
      setTimeout(() => { server.stop(); process.exit(0); }, 250);
      return Response.json({ ok: true });
    }

    return new Response("not found", { status: 404 });
  },
});

const url = `http://localhost:${server.port}/`;
console.error(url);
console.error(`answer -> ${opt.answer}`);

if (opt.open) openBrowser(url);

const watchdog = setTimeout(() => {
  console.error(`timeout after ${opt.timeoutSec}s — no submission received`);
  server.stop();
  process.exit(1);
}, opt.timeoutSec * 1000);
watchdog.unref();

function openBrowser(target: string) {
  const opener = process.platform === "darwin" ? "open"
               : process.platform === "win32"  ? "cmd"
               : "xdg-open";
  const args = process.platform === "win32" ? ["/c", "start", "", target] : [target];
  try {
    spawn(opener, args, { detached: true, stdio: "ignore" }).unref();
  } catch (e) {
    console.error(`(could not auto-open browser: ${e})`);
  }
}
