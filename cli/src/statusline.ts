import { execFileSync } from "child_process";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { basename } from "path";
import { ensureDirs, getParentToolPid, paths } from "./paths.js";
import type { Session, StatusInput } from "./types.js";
import { readStdin } from "./utils.js";

// ANSI color codes
const CYAN = "\x1b[36m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const MAGENTA = "\x1b[35m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";

function formatTokens(tokens: number): string {
  const k = tokens / 1000;
  if (k < 1) return `${tokens}`;
  if (k < 10) return `${k.toFixed(1)}k`;
  return `${Math.round(k)}k`;
}

function getContextColor(used: number): string {
  if (used < 50) return GREEN;
  if (used < 80) return YELLOW;
  return RED;
}

function getGitBranch(cwd: string): string | undefined {
  try {
    return execFileSync(
      "git",
      ["-c", "core.useBuiltinFSMonitor=false", "branch", "--show-current"],
      { cwd, encoding: "utf-8", timeout: 2000, stdio: ["pipe", "pipe", "pipe"] },
    ).trim() || undefined;
  } catch {
    return undefined;
  }
}

export async function statusCommand(): Promise<void> {
  await ensureDirs();

  const input = await readStdin();
  if (!input.trim()) return;

  let parsed: StatusInput;
  try {
    parsed = JSON.parse(input);
  } catch {
    return;
  }

  if (!parsed.session_id) return;

  const model = parsed.model?.display_name;
  const cwd = parsed.workspace?.current_dir;
  const costUsd = parsed.cost?.total_cost_usd ?? 0;
  const usedPct = parsed.context_window?.used_percentage ?? 0;
  const ctxSize = parsed.context_window?.context_window_size;
  const tokensUsed = ctxSize != null && usedPct > 0
    ? Math.round(ctxSize * usedPct / 100)
    : undefined;

  // Read existing session file and merge status data
  const sessionPath = paths.sessionFile(parsed.session_id);
  let session: Session | undefined;

  if (existsSync(sessionPath)) {
    try {
      session = JSON.parse(readFileSync(sessionPath, "utf-8"));
    } catch {
      // fall through to default
    }
  }

  session ??= {
    sessionId: parsed.session_id,
    cwd: cwd ?? "",
    state: "working",
    costUsd: 0,
    contextPct: 0,
    lastUpdatedAt: new Date().toISOString(),
  };

  if (model) session.model = model;
  if (cwd) session.cwd = cwd;
  session.costUsd = costUsd;
  session.contextPct = usedPct;
  if (tokensUsed != null) session.contextTokens = tokensUsed;
  session.provider ??= "claude";
  session.pid = getParentToolPid();
  session.lastUpdatedAt = new Date().toISOString();

  writeFileSync(sessionPath, JSON.stringify(session) + "\n");

  // Build status line output
  const parts: string[] = [];

  if (model) {
    parts.push(`${CYAN}\u{1F916} ${model}${RESET}`);
  }

  if (cwd) {
    parts.push(`${BLUE}\u{1F4C1} ${basename(cwd)}${RESET}`);
  }

  if (cwd) {
    const branch = getGitBranch(cwd);
    if (branch) {
      parts.push(`${MAGENTA}\u{1F33F} ${branch}${RESET}`);
    }
  }

  if (usedPct > 0) {
    const ctxColor = getContextColor(usedPct);
    const tokenStr = tokensUsed != null ? ` (${formatTokens(tokensUsed)})` : "";
    parts.push(`${ctxColor}\u{1F4AD} ${Math.round(usedPct)}%${tokenStr} used${RESET}`);
  }

  if (costUsd > 0) {
    parts.push(`${YELLOW}\u{1F4B0} $${costUsd.toFixed(4)}${RESET}`);
  }

  process.stdout.write(parts.join(" \u{2502} ") + "\n");

  // Set terminal window/tab title to the directory name
  if (cwd) {
    process.stderr.write(`\x1b]0;${basename(cwd)}\x07`);
  }
}
