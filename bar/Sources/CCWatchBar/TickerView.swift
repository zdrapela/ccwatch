import AppKit

struct TickerView {
    static func sortedSessions(_ sessions: [Session]) -> [Session] {
        sessions
            .sorted { a, b in stateOrder(a.state) < stateOrder(b.state) }
    }

    static func snapshotString(sessions: [Session]) -> String {
        sessions.map { s in
            "\(s.sessionId)|\(s.state.rawValue)|\(s.cwd)|\(s.model ?? "")|\(s.costUsd)|\(s.contextPct)|\(s.currentTool ?? "")|\(s.lastUpdatedAt)"
        }.joined(separator: "\n")
    }

    // Line 1: icon + project name
    static func titleLine(_ session: Session) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let icon = stateIcon(session.state)
        let project = projectName(session.cwd)

        result.append(NSAttributedString(
            string: "\(icon) ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        ))

        result.append(NSAttributedString(
            string: project,
            attributes: [
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        ))

        return result
    }

    // Line 2: model · cost · ctx%  · tool
    static func detailLine(_ session: Session) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let dimBlack = NSColor.black.withAlphaComponent(0.55)
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        let sep = " \u{00B7} "

        var parts: [String] = []

        if let model = session.model, !model.isEmpty {
            parts.append(shortenModel(model))
        }

        parts.append(String(format: "$%.2f", session.costUsd))
        parts.append("ctx:\(Int(session.contextPct))%")

        if let tool = session.currentTool, !tool.isEmpty {
            parts.append(tool)
        }

        let joined = parts.joined(separator: sep)
        result.append(NSAttributedString(
            string: joined,
            attributes: [.foregroundColor: dimBlack, .font: font]
        ))

        return result
    }

    private static func stateOrder(_ state: SessionState) -> Int {
        switch state {
        case .working: return 0
        case .waitingPermission: return 1
        case .waitingInput: return 2
        }
    }

    private static func stateIcon(_ state: SessionState) -> String {
        switch state {
        case .working: return "🔨"
        case .waitingPermission: return "🔐"
        case .waitingInput: return "⌨️"
        }
    }

    private static func shortenModel(_ model: String) -> String {
        // Strip provider prefix (e.g. "anthropic/")
        let name: String
        if let idx = model.lastIndex(of: "/") {
            name = String(model[model.index(after: idx)...])
        } else {
            name = model
        }

        // claude-opus-4-6@default -> Opus 4.6
        let p1 = try? NSRegularExpression(pattern: "^claude-(\\w+)-(\\d+)-(\\d+)(?:[-@].+)?$", options: .caseInsensitive)
        if let match = p1?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            let variant = (name as NSString).substring(with: match.range(at: 1)).capitalized
            let major = (name as NSString).substring(with: match.range(at: 2))
            let minor = (name as NSString).substring(with: match.range(at: 3))
            return "\(variant) \(major).\(minor)"
        }

        // claude-3-5-haiku-20241022 -> Haiku 3.5
        let p2 = try? NSRegularExpression(pattern: "^claude-(\\d+)-(\\d+)-(\\w+)(?:-\\d{8})?(?:[-@].+)?$", options: .caseInsensitive)
        if let match = p2?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            let major = (name as NSString).substring(with: match.range(at: 1))
            let minor = (name as NSString).substring(with: match.range(at: 2))
            let variant = (name as NSString).substring(with: match.range(at: 3)).capitalized
            return "\(variant) \(major).\(minor)"
        }

        // claude-opus-4.6 -> Opus 4.6
        let p3 = try? NSRegularExpression(pattern: "^claude-(\\w+)-(\\d+\\.\\d+)(?:[-@].+)?$", options: .caseInsensitive)
        if let match = p3?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            let variant = (name as NSString).substring(with: match.range(at: 1)).capitalized
            let version = (name as NSString).substring(with: match.range(at: 2))
            return "\(variant) \(version)"
        }

        // Fallback: strip @default and date suffixes
        return name
            .replacingOccurrences(of: "@default", with: "")
            .replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
    }

    private static func projectName(_ cwd: String) -> String {
        if cwd.isEmpty { return "unknown" }
        return (cwd as NSString).lastPathComponent
    }
}
