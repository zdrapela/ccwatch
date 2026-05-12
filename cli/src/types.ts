export type SessionState = "working" | "waiting:permission" | "waiting:input";

export type Provider = "claude" | "opencode" | "unknown";

export interface Session {
  sessionId: string;
  provider?: Provider;
  cwd: string;
  state: SessionState;
  currentTool?: string;
  model?: string;
  costUsd: number;
  contextPct: number;
  contextTokens?: number;
  startedAt?: string;
  lastUpdatedAt: string;
  pid?: number;
}

export interface HookInput {
  hook_event_name: string;
  session_id: string;
  cwd?: string;
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  notification_type?: string;
}

export interface StatusInput {
  session_id: string;
  model?: {
    display_name?: string;
  };
  workspace?: {
    current_dir?: string;
  };
  cost?: {
    total_cost_usd?: number;
  };
  context_window?: {
    used_percentage?: number;
    context_window_size?: number;
    total_input_tokens?: number;
    total_output_tokens?: number;
    current_usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
}
