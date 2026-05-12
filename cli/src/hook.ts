import { existsSync, readFileSync, unlinkSync, writeFileSync } from "fs";
import { ensureDirs, getParentToolPid, paths } from "./paths.js";
import type { HookInput, Session, SessionState } from "./types.js";
import { readStdin } from "./utils.js";

function extractDetail(input: HookInput): string | undefined {
  if (!input.tool_input) return undefined;
  const ti = input.tool_input;
  if (typeof ti.file_path === "string") return ti.file_path;
  if (typeof ti.command === "string") {
    const cmd = ti.command as string;
    return cmd.length > 80 ? cmd.slice(0, 77) + "..." : cmd;
  }
  if (typeof ti.pattern === "string") return ti.pattern;
  if (typeof ti.query === "string") return ti.query;
  return undefined;
}

function readSession(sessionId: string): Session | undefined {
  const filePath = paths.sessionFile(sessionId);
  if (!existsSync(filePath)) return undefined;
  try {
    return JSON.parse(readFileSync(filePath, "utf-8"));
  } catch {
    return undefined;
  }
}

function writeSession(session: Session): void {
  writeFileSync(paths.sessionFile(session.sessionId), JSON.stringify(session) + "\n");
}

export async function hookCommand(): Promise<void> {
  await ensureDirs();

  const input = await readStdin();
  if (!input.trim()) return;

  let parsed: HookInput;
  try {
    parsed = JSON.parse(input);
  } catch {
    return;
  }

  if (!parsed.session_id || !parsed.hook_event_name) return;

  const event = parsed.hook_event_name;

  // SessionEnd: delete session file
  if (event === "SessionEnd") {
    const filePath = paths.sessionFile(parsed.session_id);
    try {
      unlinkSync(filePath);
    } catch {
      // already gone
    }
    return;
  }

  // SessionStart: create or update session file
  if (event === "SessionStart") {
    const now = new Date().toISOString();
    const existing = readSession(parsed.session_id);
    const session: Session = existing ?? {
      sessionId: parsed.session_id,
      provider: "claude",
      cwd: parsed.cwd ?? "",
      state: "working",
      costUsd: 0,
      contextPct: 0,
      lastUpdatedAt: now,
    };
    session.state = "working";
    session.provider ??= "claude";
    session.startedAt ??= now;
    session.lastUpdatedAt = now;
    session.pid = getParentToolPid();
    if (parsed.cwd) session.cwd = parsed.cwd;
    session.currentTool = undefined;
    writeSession(session);
    return;
  }

  // Determine new state
  let state: SessionState;
  if (event === "Notification") {
    state =
      parsed.notification_type === "permission_prompt"
        ? "waiting:permission"
        : "waiting:input";
  } else if (event === "Stop") {
    state = "waiting:input";
  } else {
    // UserPromptSubmit, PreToolUse, PostToolUse
    state = "working";
  }

  // Read existing session or create new
  const now = new Date().toISOString();
  const existing = readSession(parsed.session_id);
  const session: Session = existing ?? {
    sessionId: parsed.session_id,
    provider: "claude",
    cwd: parsed.cwd ?? "",
    state,
    costUsd: 0,
    contextPct: 0,
    lastUpdatedAt: now,
  };

  session.state = state;
  session.provider ??= "claude";
  session.lastUpdatedAt = new Date().toISOString();
  session.pid = getParentToolPid();
  if (parsed.cwd) session.cwd = parsed.cwd;

  // Capture currentTool from PreToolUse, clear on other events
  if (event === "PreToolUse" && parsed.tool_name) {
    const detail = extractDetail(parsed);
    session.currentTool = detail ? `${parsed.tool_name} ${detail}` : parsed.tool_name;
  } else {
    session.currentTool = undefined;
  }

  writeSession(session);
}
