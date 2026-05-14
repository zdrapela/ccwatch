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

final class OverlayWindow: NSPanel {
    static let panelWidth: CGFloat = 280
    static let sessionRowHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 8
    static let margin: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let emptyHeight: CGFloat = 40

    private let vibrancyView = NSVisualEffectView()
    private var moveObserver: Any?

    /// Called when the user finishes dragging the panel to a new custom position.
    var onPositionChanged: (() -> Void)?

    private(set) var isInMoveMode = false

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
        ignoresMouseEvents = true
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    var panelContentView: NSView {
        vibrancyView
    }

    // MARK: - Move Mode

    func enterMoveMode() {
        guard !isInMoveMode else { return }
        isInMoveMode = true
        ignoresMouseEvents = false
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
        ignoresMouseEvents = true
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
    }

    // MARK: - Sizing & Positioning

    func resizeToHeight(_ newHeight: CGFloat) {
        let h = max(newHeight, Self.emptyHeight)

        if corner == .custom, let origin = customOrigin {
            // Keep the top edge anchored: top = origin.y + oldHeight
            let topEdge = origin.y + frame.height
            let newY = topEdge - h
            let newOrigin = NSPoint(x: origin.x, y: newY)
            customOrigin = newOrigin
            setFrame(NSRect(x: newOrigin.x, y: newOrigin.y, width: Self.panelWidth, height: h), display: true)
        } else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = computeOrigin(screen: screen, height: h)
            setFrame(NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: h), display: true)
        }
    }

    func reposition() {
        if corner == .custom, let origin = customOrigin {
            setFrame(NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: frame.height), display: true)
            return
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = computeOrigin(screen: screen, height: frame.height)
        setFrame(NSRect(x: origin.x, y: origin.y, width: Self.panelWidth, height: frame.height), display: true)
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
        let m = Self.margin
        let x: CGFloat
        let y: CGFloat

        switch corner {
        case .bottomRight:
            x = screen.maxX - Self.panelWidth - m
            y = screen.origin.y + m
        case .bottomLeft:
            x = screen.origin.x + m
            y = screen.origin.y + m
        case .topRight:
            x = screen.maxX - Self.panelWidth - m
            y = screen.maxY - height - m
        case .topLeft:
            x = screen.origin.x + m
            y = screen.maxY - height - m
        case .custom:
            // Shouldn't reach here — custom is handled in reposition/resize
            return customOrigin ?? NSPoint(x: screen.maxX - Self.panelWidth - m, y: screen.origin.y + m)
        }

        return NSPoint(x: x, y: y)
    }

    @objc private func screenDidChange() {
        reposition()
    }
}
