import AppKit

enum PanelCorner: String {
    case bottomRight = "bottom-right"
    case bottomLeft = "bottom-left"
    case topRight = "top-right"
    case topLeft = "top-left"
    case custom = "custom"

    static let presets: [PanelCorner] = [.bottomRight, .bottomLeft, .topRight, .topLeft]

    var label: String {
        switch self {
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        case .custom: return "Custom Position"
        }
    }
}

private enum PanelState {
    case expanded
    case collapsed
}

final class OverlayWindow: NSPanel {
    static let panelWidth: CGFloat = 280
    static let miniWidth: CGFloat = 100
    static let sessionRowHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 8
    static let margin: CGFloat = 16
    static let bottomMargin: CGFloat = 32
    static let cornerRadius: CGFloat = 12
    static let emptyHeight: CGFloat = 40

    private let vibrancyView = ClickThroughView()
    private var moveObserver: Any?
    private var mouseTrackingArea: NSTrackingArea?
    private var panelState: PanelState = .expanded
    private var isAnimating = false
    private var expandedFrame: NSRect = .zero

    /// Called when the user finishes dragging the panel to a new custom position.
    var onPositionChanged: (() -> Void)?

    private(set) var isInMoveMode = false

    var autoHide: Bool = false {
        didSet {
            if autoHide && !isInMoveMode {
                collapse()
            } else if !autoHide {
                expand()
            }
        }
    }

    /// The saved custom origin (top-left in screen coords, stored as the
    /// macOS frame origin which is bottom-left).
    private var customOrigin: NSPoint?

    var corner: PanelCorner {
        didSet { reposition() }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "panelCorner") ?? PanelCorner.bottomRight.rawValue
        corner = PanelCorner(rawValue: saved) ?? .bottomRight

        if corner == .custom {
            let x = UserDefaults.standard.double(forKey: "panelCustomX")
            let y = UserDefaults.standard.double(forKey: "panelCustomY")
            if x != 0 || y != 0 {
                customOrigin = NSPoint(x: x, y: y)
            }
        }

        let frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.emptyHeight)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        vibrancyView.material = .hudWindow
        vibrancyView.blendingMode = .behindWindow
        vibrancyView.state = .active
        vibrancyView.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        vibrancyView.autoresizingMask = [.width, .height]
        vibrancyView.wantsLayer = true
        vibrancyView.layer?.cornerRadius = Self.cornerRadius
        vibrancyView.layer?.masksToBounds = true

        contentView = vibrancyView

        reposition()
        expandedFrame = self.frame
        updateCornerMask()

        autoHide = UserDefaults.standard.bool(forKey: "autoHide")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        refreshTrackingArea()
    }

    var panelContentView: NSView {
        vibrancyView
    }

    // MARK: - Corner Mask

    /// Determine which side of the screen the panel is on.
    /// Returns true if the panel is on the right half.
    func isOnRightSide() -> Bool {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return expandedFrame.midX >= screen.midX
    }

    /// Round only the corners on the inner side (away from screen edge).
    /// The edge side stays square and flush against the screen border.
    private func updateCornerMask() {
        guard let layer = vibrancyView.layer else { return }
        layer.cornerRadius = Self.cornerRadius

        if isOnRightSide() {
            // Right side flush — round left corners only
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        } else {
            // Left side flush — round right corners only
            layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
    }

    // MARK: - Auto-hide

    private func miniFrame() -> NSRect {
        let x: CGFloat
        if isOnRightSide() {
            // Right-side panel: keep right edge aligned with expanded right edge
            x = expandedFrame.maxX - Self.miniWidth
        } else {
            // Left-side panel: keep left edge aligned with expanded left edge
            x = expandedFrame.origin.x
        }
        return NSRect(
            x: x,
            y: expandedFrame.origin.y,
            width: Self.miniWidth,
            height: expandedFrame.height
        )
    }

    func collapse() {
        guard panelState != .collapsed, !isAnimating else { return }
        expandedFrame = frame
        panelState = .collapsed
        isAnimating = true

        let target = miniFrame()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.setFrame(target, display: true)
            self.isAnimating = false
            self.refreshTrackingArea()
        }
    }

    func expand() {
        guard panelState != .expanded, !isAnimating else { return }
        panelState = .expanded
        isAnimating = true

        let target = expandedFrame
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.setFrame(target, display: true)
            self.isAnimating = false
            self.refreshTrackingArea()
        }
    }

    // MARK: - Mouse Tracking

    private func refreshTrackingArea() {
        if let existing = mouseTrackingArea {
            vibrancyView.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: vibrancyView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        vibrancyView.addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if autoHide && panelState == .collapsed && !isInMoveMode && !isAnimating {
            expand()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if autoHide && panelState == .expanded && !isInMoveMode && !isAnimating {
            collapse()
        }
    }

    // MARK: - Move Mode

    func enterMoveMode() {
        guard !isInMoveMode else { return }
        isInMoveMode = true

        // Ensure expanded while moving
        if panelState == .collapsed {
            expand()
        }

        vibrancyView.interactiveMode = true
        isMovableByWindowBackground = true

        // Visual indicator: highlight border
        vibrancyView.layer?.borderWidth = 2
        vibrancyView.layer?.borderColor = NSColor.controlAccentColor.cgColor

        // Track window moves to capture the final position
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isInMoveMode else { return }
            self.customOrigin = self.frame.origin
        }
    }

    func exitMoveMode() {
        guard isInMoveMode else { return }
        isInMoveMode = false
        vibrancyView.interactiveMode = false
        isMovableByWindowBackground = false

        // Remove highlight
        vibrancyView.layer?.borderWidth = 0

        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
            moveObserver = nil
        }

        // Save the custom position if the user actually moved it
        if let origin = customOrigin {
            corner = .custom
            UserDefaults.standard.set(corner.rawValue, forKey: "panelCorner")
            UserDefaults.standard.set(Double(origin.x), forKey: "panelCustomX")
            UserDefaults.standard.set(Double(origin.y), forKey: "panelCustomY")
            onPositionChanged?()
        }

        // Update expandedFrame after move
        expandedFrame = frame
        updateCornerMask()

        // Re-collapse if auto-hide is on
        if autoHide {
            collapse()
        }
    }

    // MARK: - Sizing & Positioning

    func resizeToHeight(_ newHeight: CGFloat) {
        let h = max(newHeight, Self.emptyHeight)

        if corner == .custom, let origin = customOrigin {
            // Keep the top edge anchored: top = origin.y + oldHeight
            let topEdge = origin.y + expandedFrame.height
            let newY = topEdge - h
            let newOrigin = NSPoint(x: origin.x, y: newY)
            customOrigin = newOrigin
            expandedFrame = NSRect(x: newOrigin.x, y: newOrigin.y, width: Self.panelWidth, height: h)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = computeOrigin(screen: screen, height: h)
            expandedFrame = NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: h)
        }

        if panelState == .collapsed && autoHide {
            // Update mini frame with new height
            setFrame(miniFrame(), display: true)
        } else {
            setFrame(expandedFrame, display: true)
        }

        updateCornerMask()
        refreshTrackingArea()
    }

    func reposition() {
        if corner == .custom, let origin = customOrigin {
            expandedFrame = NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: frame.height)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = computeOrigin(screen: screen, height: frame.height)
            expandedFrame = NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: frame.height)
        }

        if panelState == .collapsed && autoHide {
            setFrame(miniFrame(), display: true)
        } else {
            setFrame(expandedFrame, display: true)
        }

        updateCornerMask()
        refreshTrackingArea()
    }

    /// Switch to a preset corner (clears custom position).
    func setPresetCorner(_ preset: PanelCorner) {
        customOrigin = nil
        corner = preset
        UserDefaults.standard.set(preset.rawValue, forKey: "panelCorner")
        UserDefaults.standard.removeObject(forKey: "panelCustomX")
        UserDefaults.standard.removeObject(forKey: "panelCustomY")
    }

    private func computeOrigin(screen: NSRect, height: CGFloat) -> NSPoint {
        let bm = Self.bottomMargin
        let vm = Self.margin  // vertical margin for top corners
        let x: CGFloat
        let y: CGFloat

        switch corner {
        case .bottomRight:
            x = screen.maxX - Self.panelWidth  // flush right
            y = screen.origin.y + bm
        case .bottomLeft:
            x = screen.origin.x                // flush left
            y = screen.origin.y + bm
        case .topRight:
            x = screen.maxX - Self.panelWidth  // flush right
            y = screen.maxY - height - vm
        case .topLeft:
            x = screen.origin.x                // flush left
            y = screen.maxY - height - vm
        case .custom:
            return customOrigin ?? NSPoint(x: screen.maxX - Self.panelWidth, y: screen.origin.y + bm)
        }

        return NSPoint(x: x, y: y)
    }

    @objc private func screenDidChange() {
        reposition()
    }
}
