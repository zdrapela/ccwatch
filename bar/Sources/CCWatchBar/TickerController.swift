import AppKit

final class TickerController {
    private var subviews: [NSView] = []
    private weak var containerView: NSView?
    private var lastContentSnapshot: String = ""
    var onLayoutChanged: ((CGFloat) -> Void)?
    var onWorkspaceClicked: ((String) -> Void)?
    var isRightSide: Bool = true

    func attach(to view: NSView) {
        containerView = view
    }

    func update(sessions: [Session]) {
        guard let container = containerView else { return }

        let sorted = sessions.sorted { a, b in
            if a.cwd != b.cwd { return a.cwd < b.cwd }
            return a.sessionId < b.sessionId
        }
        let snapshot = TickerView.snapshotString(sessions: sorted)
        if snapshot == lastContentSnapshot {
            return
        }
        lastContentSnapshot = snapshot

        // Clear
        for v in subviews { v.removeFromSuperview() }
        subviews.removeAll()

        let panelWidth = container.bounds.width
        let hPadding: CGFloat = 14

        let groups = TickerView.groupedSessions(sessions)

        if groups.isEmpty {
            let totalHeight = OverlayWindow.emptyHeight
            onLayoutChanged?(totalHeight)

            let field = makeLabel()
            field.attributedStringValue = NSAttributedString(
                string: "No active sessions",
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                ]
            )
            field.alignment = .center
            field.frame = NSRect(x: 0, y: 0, width: panelWidth, height: totalHeight)
            container.addSubview(field)
            subviews.append(field)
            return
        }

        let totalHeight = TickerView.totalHeight(groups: groups)
        onLayoutChanged?(totalHeight)

        // Render top-down: start from the top
        var y = totalHeight - 8  // top padding

        for (gi, group) in groups.enumerated() {
            // Group header (clickable — opens workspace in editor)
            y -= TickerView.groupHeaderHeight
            let headerAttrs = TickerView.groupHeaderAttributes()
            let header = ClickableLabel(
                string: TickerView.projectName(group.cwd),
                attributes: headerAttrs
            )
            header.frame = NSRect(x: hPadding, y: y + 4, width: panelWidth - hPadding * 2, height: 16)
            if isRightSide {
                header.alignment = .right
                header.lineBreakMode = .byClipping
            }
            let cwd = group.cwd
            header.onClick = { [weak self] in
                self?.onWorkspaceClicked?(cwd)
            }
            container.addSubview(header)
            subviews.append(header)

            // Sessions in this group
            for session in group.sessions {
                y -= TickerView.sessionRowHeight

                // Session line 1: icons + model · cost · ctx
                let line1 = makeLabel()
                line1.attributedStringValue = TickerView.sessionLine(session)
                line1.frame = NSRect(x: hPadding + 8, y: y + 20, width: panelWidth - hPadding * 2 - 8, height: 16)
                if isRightSide { line1.lineBreakMode = .byClipping }
                container.addSubview(line1)
                subviews.append(line1)

                // Session line 2: tool/status detail
                let line2 = makeLabel()
                line2.attributedStringValue = TickerView.sessionDetailLine(session)
                line2.frame = NSRect(x: hPadding + 28, y: y + 4, width: panelWidth - hPadding * 2 - 28, height: 14)
                if isRightSide { line2.lineBreakMode = .byClipping }
                container.addSubview(line2)
                subviews.append(line2)
            }

            // Separator between groups (not after last)
            if gi < groups.count - 1 {
                y -= TickerView.groupSpacing / 2
                let sep = NSView(frame: NSRect(
                    x: hPadding,
                    y: y - 0.5,
                    width: panelWidth - hPadding * 2,
                    height: 1
                ))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
                container.addSubview(sep)
                subviews.append(sep)
                y -= TickerView.groupSpacing / 2
            }
        }
    }

    private func makeLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.truncatesLastVisibleLine = true
        return field
    }
}
