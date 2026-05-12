import { existsSync, readdirSync, readFileSync, unlinkSync } from "fs";
import { hasRunningToolProcess, paths } from "./paths.js";
import type { Session } from "./types.js";

// Only used as a last resort for sessions with no PID when no tool process is found
const STALE_TIMEOUT_MS = 60 * 60 * 1000; // 1 hour

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0); // signal 0 = just check existence
    return true;
  } catch (e: unknown) {
    // EPERM means the process exists but we can't signal it
    if (e && typeof e === "object" && "code" in e && (e as { code: string }).code === "EPERM") {
      return true;
    }
    return false;
  }
}

// Cache the hasRunningToolProcess() result for up to 5 seconds
// to avoid running ps on every TUI render (1/sec).
let _toolAliveCache: { result: boolean; ts: number } | null = null;

function isAnyToolAlive(): boolean {
  const now = Date.now();
  if (_toolAliveCache && now - _toolAliveCache.ts < 5000) {
    return _toolAliveCache.result;
  }
  const result = hasRunningToolProcess();
  _toolAliveCache = { result, ts: now };
  return result;
}

export function deriveSessions(): Session[] {
  if (!existsSync(paths.sessionsDir)) return [];

  const sessions: Session[] = [];
  const pendingCleanup: string[] = [];
  const now = Date.now();

  for (const file of readdirSync(paths.sessionsDir)) {
    if (!file.endsWith(".json")) continue;
    const sessionId = file.replace(".json", "");
    try {
      const content = readFileSync(paths.sessionFile(sessionId), "utf-8");
      const session: Session = JSON.parse(content);

      // If we have a PID, check if the process is still alive.
      // Alive -> show, dead -> clean up immediately.
      if (session.pid) {
        if (!isProcessAlive(session.pid)) {

          try {
            unlinkSync(paths.sessionFile(sessionId));
          } catch {
            // ignore
          }
          continue;
        }
        sessions.push(session);
        continue;
      }

      // No PID: defer cleanup decision until we check for running tool processes.
      const lastUpdate = new Date(session.lastUpdatedAt).getTime();
      if (now - lastUpdate > STALE_TIMEOUT_MS) {
        pendingCleanup.push(sessionId);
      } else {
        sessions.push(session);
      }
    } catch {
      // skip unreadable files
    }
  }

  // For sessions without PIDs that exceeded the stale timeout,
  // only clean up if no AI coding tool process is running at all.
  // This prevents removing sessions where PID detection failed.
  if (pendingCleanup.length > 0) {
    if (isAnyToolAlive()) {
      // A tool process is running -- keep these sessions, don't delete
      for (const sessionId of pendingCleanup) {
        try {
          const content = readFileSync(paths.sessionFile(sessionId), "utf-8");
          sessions.push(JSON.parse(content));
        } catch {
          // skip
        }
      }
    } else {
      // No tool processes found -- safe to clean up
      for (const sessionId of pendingCleanup) {
        try {
          unlinkSync(paths.sessionFile(sessionId));
        } catch {
          // ignore
        }
      }
    }
  }

  return sessions;
}
