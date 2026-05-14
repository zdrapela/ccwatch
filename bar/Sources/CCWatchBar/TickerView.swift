import AppKit

struct SessionGroup {
    let cwd: String
    let sessions: [Session]
}

struct TickerView {
    static let groupHeaderHeight: CGFloat = 22
    static let sessionRowHeight: CGFloat = 38
    static let groupSpacing: CGFloat = 4

    static func groupedSessions(_ sessions: [Session]) -> [SessionGroup] {
        // Group by cwd
        var map: [String: [Session]] = [:]
        var order: [String] = []
        for s in sessions {
            let key = s.cwd.isEmpty ? "(unknown)" : s.cwd
            if map[key] == nil {
                map[key] = []
                order.append(key)
            }
            map[key]!.append(s)
        }

        var groups: [SessionGroup] = []
        for key in order {
            var cwdSessions = map[key]!
            cwdSessions.sort { a, b in stateOrder(a.state) < stateOrder(b.state) }
            groups.append(SessionGroup(cwd: key, sessions: cwdSessions))
        }

        // Sort groups: groups with any working session first, then by path
        groups.sort { a, b in
            let aWorking = a.sessions.contains { $0.state == .working } ? 0 : 1
            let bWorking = b.sessions.contains { $0.state == .working } ? 0 : 1
            if aWorking != bWorking { return aWorking < bWorking }
            return a.cwd < b.cwd
        }

        return groups
    }

    /// Total panel height needed for the grouped layout.
    static func totalHeight(groups: [SessionGroup]) -> CGFloat {
        if groups.isEmpty { return 0 }
        var h: CGFloat = 8 // top padding
        for (i, group) in groups.enumerated() {
            h += groupHeaderHeight
            h += CGFloat(group.sessions.count) * sessionRowHeight
            if i < groups.count - 1 {
                h += groupSpacing
            }
        }
        h += 8 // bottom padding
        return h
    }

    static func snapshotString(sessions: [Session]) -> String {
        sessions.map { s in
            "\(s.sessionId)|\(s.provider?.rawValue ?? "")|\(s.state.rawValue)|\(s.cwd)|\(s.model ?? "")|\(s.costUsd)|\(s.contextPct)|\(s.currentTool ?? "")|\(s.lastUpdatedAt)"
        }.joined(separator: "\n")
    }

    // Group header: project name
    static func groupHeaderLine(_ cwd: String) -> NSAttributedString {
        let project = projectName(cwd)
        return NSAttributedString(
            string: project,
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.8),
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            ]
        )
    }

    // Session line 1: stateIcon providerIcon  model · cost · ctx%
    static func sessionLine(_ session: Session) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let icon = stateIcon(session.state)
        let pIcon = providerIcon(session.provider)

        result.append(NSAttributedString(
            string: "\(icon)\(pIcon) ",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        ))

        let dimBlack = NSColor.black.withAlphaComponent(0.6)
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        let sep = " \u{00B7} "

        var parts: [String] = []
        if let model = session.model, !model.isEmpty {
            parts.append(shortenModel(model))
        }
        parts.append(String(format: "$%.2f", session.costUsd))
        parts.append("ctx:\(Int(session.contextPct))%")

        result.append(NSAttributedString(
            string: parts.joined(separator: sep),
            attributes: [.foregroundColor: dimBlack, .font: font]
        ))

        return result
    }

    // Session line 2: tool/status detail
    static func sessionDetailLine(_ session: Session) -> NSAttributedString {
        let dimBlack = NSColor.black.withAlphaComponent(0.45)
        let font = NSFont.systemFont(ofSize: 10, weight: .regular)

        let detail: String
        if let tool = session.currentTool, !tool.isEmpty {
            detail = tool
        } else {
            switch session.state {
            case .working: detail = "Processing..."
            case .waitingPermission: detail = "Permission requested"
            case .waitingInput: detail = "Waiting for input"
            }
        }

        return NSAttributedString(
            string: detail,
            attributes: [.foregroundColor: dimBlack, .font: font]
        )
    }

    private static func stateOrder(_ state: SessionState) -> Int {
        switch state {
        case .working: return 0
        case .waitingPermission: return 1
        case .waitingInput: return 2
        }
    }

    private static func providerIcon(_ provider: Provider?) -> String {
        switch provider {
        case .claude: return "🟠"
        case .opencode: return "🟣"
        default: return "⚪"
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
