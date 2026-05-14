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

function shortenModel(model: string): string {
  // Strip provider prefixes (e.g. "anthropic/", "google-vertex-anthropic/")
  const name = model.replace(/^[a-z0-9.-]+\//, "");
  // claude-opus-4-6@default -> Opus 4.6
  const m1 = name.match(/^claude-(\w+)-(\d+)-(\d+)(?:[-@].+)?$/i);
  if (m1) {
    const variant = m1[1].charAt(0).toUpperCase() + m1[1].slice(1).toLowerCase();
    return `${variant} ${m1[2]}.${m1[3]}`;
  }
  // claude-3-5-haiku-20241022 -> Haiku 3.5
  const m2 = name.match(/^claude-(\d+)-(\d+)-(\w+)(?:-\d{8})?(?:[-@].+)?$/i);
  if (m2) {
    const variant = m2[3].charAt(0).toUpperCase() + m2[3].slice(1).toLowerCase();
    return `${variant} ${m2[1]}.${m2[2]}`;
  }
  // claude-opus-4.6 -> Opus 4.6
  const m3 = name.match(/^claude-(\w+)-(\d+\.\d+)(?:[-@].+)?$/i);
  if (m3) {
    const variant = m3[1].charAt(0).toUpperCase() + m3[1].slice(1).toLowerCase();
    return `${variant} ${m3[2]}`;
  }
  // Already short (e.g. "Opus 4" from Claude Code statusLine)
  return name.replace(/@default$/, "").replace(/-\d{8}$/, "");
}

function formatTokens(tokens: number): string {
  const k = tokens / 1000;
  if (k < 1) return `${tokens}`;
  if (k < 10) return `${k.toFixed(1)}k`;
  return `${Math.round(k)}k`;
}

function providerIcon(provider?: string): string {
  switch (provider) {
    case "claude": return "\uD83D\uDFE0";
    case "opencode": return "\uD83D\uDFE3";
    default: return "\u26AA";
  }
}

function renderGroupHeader(cwd: string, width: number): string {
  const path = shortenPath(cwd);
  return `  ${BOLD}${path}${RESET}`;
}

function renderSessionRow(session: Session, width: number): string {
  const color = stateColor(session.state);
  const icon = stateIcon(session.state);
  const label = stateLabel(session.state);
  const pIcon = providerIcon(session.provider);
  const model = session.model ? shortenModel(session.model) : "";
  const cost = formatCost(session.costUsd);
  const tokenStr = session.contextTokens != null ? ` ${formatTokens(session.contextTokens)}` : "";
  const ctx = `ctx:${Math.round(session.contextPct)}%${tokenStr}`;

  // Line 1: providerIcon stateIcon STATE   model  cost  ctx
  const leftPart = `    ${pIcon} ${color}${icon} ${label}${RESET}`;
  const leftVisible = `    ${pIcon} ${icon} ${label}`;

  const rightParts: string[] = [];
  if (model) rightParts.push(model);
  rightParts.push(cost);
  rightParts.push(ctx);
  const rightStr = rightParts.join("   ");

  const padding = Math.max(1, width - leftVisible.length - rightStr.length - 2);
  const line1 = leftPart + " ".repeat(padding) + `${color}${rightStr}${RESET}`;

  // Line 2: tool/status info + time ago
  const indent = "                ";
  const detail = session.currentTool ?? statusText(session.state);
  const ago = timeAgo(session.lastUpdatedAt);
  const detailLine = `${indent}${DIM}${detail}${RESET}`;
  const agoStr = `${DIM}${ago}${RESET}`;
  const detailVisible = `${indent}${detail}`;
  const detailPadding = Math.max(1, width - detailVisible.length - ago.length - 2);

  const line2 = detailLine + " ".repeat(detailPadding) + agoStr;

  return line1 + "\n" + line2;
}

interface SessionGroup {
  cwd: string;
  sessions: Session[];
}

function groupSessions(sessions: Session[]): SessionGroup[] {
  const stateOrder: Record<SessionState, number> = {
    working: 0,
    "waiting:permission": 1,
    "waiting:input": 2,
  };

  // Group by cwd
  const map = new Map<string, Session[]>();
  for (const s of sessions) {
    const key = s.cwd || "(unknown)";
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(s);
  }

  const groups: SessionGroup[] = [];
  for (const [cwd, cwdSessions] of map) {
    // Sort sessions within group by state
    cwdSessions.sort((a, b) => stateOrder[a.state] - stateOrder[b.state]);
    groups.push({ cwd, sessions: cwdSessions });
  }

  // Sort groups: groups with any working session first, then by path
  groups.sort((a, b) => {
    const aHasWorking = a.sessions.some(s => s.state === "working") ? 0 : 1;
    const bHasWorking = b.sessions.some(s => s.state === "working") ? 0 : 1;
    if (aHasWorking !== bHasWorking) return aHasWorking - bHasWorking;
    return a.cwd.localeCompare(b.cwd);
  });

  return groups;
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
      const groups = groupSessions(sessions);
      for (const group of groups) {
        output += renderGroupHeader(group.cwd, width) + "\n";
        for (const session of group.sessions) {
          output += renderSessionRow(session, width) + "\n";
        }
        output += "\n";
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
