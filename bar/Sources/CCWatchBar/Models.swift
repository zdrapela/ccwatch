// Generated from cli/src/types.ts — do not edit manually.
// Run: bun generate-models.ts

import Foundation

enum SessionState: String, Codable {
    case working = "working"
    case waitingPermission = "waiting:permission"
    case waitingInput = "waiting:input"
}

enum Provider: String, Codable {
    case claude = "claude"
    case opencode = "opencode"
    case unknown = "unknown"
}

struct Session: Codable, Identifiable {
    var id: String { sessionId }

    let sessionId: String
    var provider: Provider?
    var cwd: String
    var state: SessionState
    var currentTool: String?
    var model: String?
    var costUsd: Double
    var contextPct: Double
    var contextTokens: Double?
    var startedAt: String?
    var lastUpdatedAt: String
    var pid: Int?
}
