import { ensureDirs } from "./paths.js";
import { deriveSessions } from "./state.js";
import type { Session, SessionState } from "./types.js";
import { FileWatcher } from "./watcher.js";

// ANSI escape codes
const ESC = "\x1b";
const RESET = `${ESC}[0m`;
const BOLD = `${ESC}[1m`;
const DIM = `${ESC}[2m`;
const GREEN = `${ESC}[32m`;
const YELLOW = `${ESC}[33m`;
const CLEAR_SCREEN = `${ESC}[2J${ESC}[H`;
const HIDE_CURSOR = `${ESC}[?25l`;
const SHOW_CURSOR = `${ESC}[?25h`;
const ALT_SCREEN_ON = `${ESC}[?1049h`;
const ALT_SCREEN_OFF = `${ESC}[?1049l`;

function stateIcon(state: SessionState): string {
  switch (state) {
    case "working":
      return "\u25CF";
    case "waiting:permission":
      return "\u23F3";
    case "waiting:input":
      return "\u2328";
  }
}

function stateColor(state: SessionState): string {
  switch (state) {
    case "working":
      return GREEN;
    case "waiting:permission":
      return `${BOLD}${YELLOW}`;
    case "waiting:input":
      return `${BOLD}${YELLOW}`;
  }
}

function stateLabel(state: SessionState): string {
  switch (state) {
    case "working":
      return "WORKING".padEnd(8);
    case "waiting:permission":
      return "BLOCKED".padEnd(8);
    case "waiting:input":
      return "INPUT".padEnd(8);
  }
}

function timeAgo(ts: string): string {
  const diff = Math.max(0, Math.floor((Date.now() - new Date(ts).getTime()) / 1000));
  if (diff < 60) return `${diff}s ago`;
  const mins = Math.floor(diff / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  return `${hours}h ago`;
}

function shortenPath(cwd: string): string {
  const home = process.env.HOME ?? "";
  if (home && cwd.startsWith(home)) {
    return "~" + cwd.slice(home.length);
  }
  return cwd;
}

function formatCost(usd: number): string {
  return `$${usd.toFixed(2)}`;
}

function formatTokens(tokens: number): string {
  const k = tokens / 1000;
  if (k < 1) return `${tokens}`;
  if (k < 10) return `${k.toFixed(1)}k`;
  return `${Math.round(k)}k`;
}

function renderSession(session: Session, width: number): string {
  const color = stateColor(session.state);
  const icon = stateIcon(session.state);
  const label = stateLabel(session.state);
  const path = shortenPath(session.cwd);
  const model = session.model ?? "";
  const cost = formatCost(session.costUsd);
  const tokenStr = session.contextTokens != null ? ` ${formatTokens(session.contextTokens)}` : "";
  const ctx = `ctx:${Math.round(session.contextPct)}%${tokenStr}`;

  // First line: icon STATE path   model  cost  ctx
  const line1Parts = [
    `  ${color}${icon} ${label}${RESET}`,
    ` ${color}${path}${RESET}`,
  ];

  const rightParts: string[] = [];
  if (model) rightParts.push(model);
  rightParts.push(cost);
  rightParts.push(ctx);
  const rightStr = rightParts.join("   ");

  // Calculate visible length of left part (without ANSI codes)
  const leftText = `  ${icon} ${label} ${path}`;
  const padding = Math.max(1, width - leftText.length - rightStr.length - 2);

  const line1 = line1Parts.join("") + " ".repeat(padding) + `${color}${rightStr}${RESET}`;

  // Second line: tool/status info + time ago
  const detail = session.currentTool ?? statusText(session.state);
  const ago = timeAgo(session.lastUpdatedAt);
  const detailLine = `              ${DIM}${detail}${RESET}`;
  const agoStr = `${DIM}${ago}${RESET}`;
  const detailVisible = `              ${detail}`;
  const detailPadding = Math.max(1, width - detailVisible.length - ago.length - 2);

  const line2 = detailLine + " ".repeat(detailPadding) + agoStr;

  return line1 + "\n" + line2;
}

function statusText(state: SessionState): string {
  switch (state) {
    case "working":
      return "Processing...";
    case "waiting:permission":
      return "Permission requested";
    case "waiting:input":
      return "Waiting for input";
  }
}

function renderFooter(sessions: Session[], width: number): string {
  const total = sessions.length;
  const totalCost = sessions.reduce((sum, s) => sum + s.costUsd, 0);
  const blocked = sessions.filter((s) => s.state === "waiting:permission").length;
  const awaitingInput = sessions.filter((s) => s.state === "waiting:input").length;

  const parts = [`${total} session${total !== 1 ? "s" : ""}`];
  parts.push(`${formatCost(totalCost)} total`);
  if (blocked > 0) {
    parts.push(`${YELLOW}${blocked} blocked${RESET}`);
  }
  if (awaitingInput > 0) {
    parts.push(`${YELLOW}${awaitingInput} awaiting input${RESET}`);
  }

  const line = "\u2500".repeat(width);
  return `${DIM}  ${line}${RESET}\n  ${DIM}${parts.join(" \u2502 ")}${RESET}`;
}

export async function startTui(): Promise<void> {
  await ensureDirs();

  // Enter alternate screen, hide cursor
  process.stdout.write(ALT_SCREEN_ON + HIDE_CURSOR);

  function render(): void {
    const width = process.stdout.columns || 80;
    const sessions = deriveSessions();

    // Sort: working first, then waiting:permission, then waiting:input
    const order: Record<SessionState, number> = {
      working: 0,
      "waiting:permission": 1,
      "waiting:input": 2,
    };
    sessions.sort((a, b) => order[a.state] - order[b.state]);

    let output = CLEAR_SCREEN;

    // Header
    output += `  ${BOLD}ccwatch${RESET}`;
    const quitHint = "q: quit";
    const headerPad = Math.max(1, (process.stdout.columns || 80) - 9 - quitHint.length - 2);
    output += " ".repeat(headerPad) + `${DIM}${quitHint}${RESET}`;
    output += "\n\n";

    if (sessions.length === 0) {
      output += `  ${DIM}No active sessions${RESET}\n`;
      output += `  ${DIM}Start Claude Code or OpenCode in another terminal to see it here.${RESET}\n`;
      output += `\n  ${DIM}Run 'ccwatch install' to set up hooks if you haven't already.${RESET}\n`;
    } else {
      for (const session of sessions) {
        output += renderSession(session, width) + "\n\n";
      }

      output += renderFooter(sessions, width - 4) + "\n";
    }

    process.stdout.write(output);
  }

  render();

  // File watcher
  const watcher = new FileWatcher(() => render());
  watcher.start();

  // Periodic refresh for timestamps
  const refreshInterval = setInterval(() => render(), 1000);

  // Keyboard input
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding("utf-8");
    process.stdin.on("data", (key: string) => {
      if (key === "q" || key === "\x03") {
        // q or Ctrl+C
        shutdown();
      }
    });
  }

  // Handle terminal resize
  process.stdout.on("resize", () => render());

  function shutdown(): void {
    watcher.stop();
    clearInterval(refreshInterval);
    process.stdout.write(SHOW_CURSOR + ALT_SCREEN_OFF);
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(false);
    }
    process.exit(0);
  }

  // Handle signals
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}
