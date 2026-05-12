import { execFileSync } from "child_process";
import { homedir } from "os";
import { join } from "path";

const CONFIG_DIR = join(homedir(), ".config", "ccwatch");
const SESSIONS_DIR = join(CONFIG_DIR, "sessions");
const CLAUDE_SETTINGS = join(homedir(), ".claude", "settings.json");
const OPENCODE_PLUGINS_DIR = join(homedir(), ".config", "opencode", "plugins");

export const paths = {
  configDir: CONFIG_DIR,
  sessionsDir: SESSIONS_DIR,
  sessionFile: (sessionId: string) => join(SESSIONS_DIR, `${sessionId}.json`),
  claude: {
    settings: CLAUDE_SETTINGS,
  },
  opencode: {
    pluginsDir: OPENCODE_PLUGINS_DIR,
    pluginFile: join(OPENCODE_PLUGINS_DIR, "ccwatch-plugin.js"),
  },
};

export async function ensureDirs(): Promise<void> {
  const { mkdir } = await import("fs/promises");
  await mkdir(paths.configDir, { recursive: true });
  await mkdir(paths.sessionsDir, { recursive: true });
}

/**
 * Check whether a command line (ps args=) looks like an AI coding tool process.
 * Matches "claude" or "opencode" as a whole word (case-insensitive) in the full
 * command line, which catches: /path/to/claude, node .../claude-code/...,
 * Claude.app, opencode, etc.
 * Excludes ccwatch's own processes.
 */
function isToolArgs(args: string): boolean {
  return /\b(claude|opencode)\b/i.test(args) && !/\bccwatch\b/i.test(args);
}

/**
 * Get the parent AI coding tool process PID by walking up the process tree
 * looking for a process whose full command line contains "claude" or "opencode".
 * Uses args= (full command line) instead of comm= (executable name only)
 * because the tool may run as a Node.js script where comm= shows "node".
 * Falls back to grandparent PID if detection fails.
 */
export function getParentToolPid(): number | undefined {
  try {
    let pid = process.ppid;
    for (let i = 0; i < 10; i++) {
      const args = execFileSync("ps", ["-o", "args=", "-p", String(pid)], {
        encoding: "utf-8",
        timeout: 2000,
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();

      if (isToolArgs(args)) {
        return pid;
      }

      const ppidOutput = execFileSync("ps", ["-o", "ppid=", "-p", String(pid)], {
        encoding: "utf-8",
        timeout: 2000,
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();
      const parentPid = parseInt(ppidOutput, 10);
      if (Number.isNaN(parentPid) || parentPid <= 1) break;
      pid = parentPid;
    }
  } catch {
    // fall through
  }
  // Fallback: grandparent PID (best-effort when name-based detection fails)
  try {
    const output = execFileSync("ps", ["-o", "ppid=", "-p", String(process.ppid)], {
      encoding: "utf-8",
      timeout: 2000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    const grandparentPid = parseInt(output.trim(), 10);
    return Number.isNaN(grandparentPid) || grandparentPid <= 1
      ? undefined
      : grandparentPid;
  } catch {
    return undefined;
  }
}

/**
 * Check if ANY AI coding tool process (Claude Code or OpenCode) is currently
 * running on the system.
 * Used as a safety net before cleaning up sessions that have no PID.
 */
export function hasRunningToolProcess(): boolean {
  try {
    const output = execFileSync("ps", ["-eo", "args="], {
      encoding: "utf-8",
      timeout: 3000,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return output.split("\n").some(line => isToolArgs(line));
  } catch {
    return false;
  }
}
