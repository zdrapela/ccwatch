import AppKit

/// A label that responds to clicks and shows hover feedback (underline + hand cursor).
final class ClickableLabel: NSTextField {
    var onClick: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private var baseAttributes: [NSAttributedString.Key: Any] = [:]

    convenience init(string: String, attributes: [NSAttributedString.Key: Any]) {
        self.init(labelWithString: "")
        self.baseAttributes = attributes
        self.attributedStringValue = NSAttributedString(string: string, attributes: attributes)
        self.isEditable = false
        self.isSelectable = false
        self.isBordered = false
        self.drawsBackground = false
        self.lineBreakMode = .byTruncatingTail
        self.maximumNumberOfLines = 1
        self.cell?.truncatesLastVisibleLine = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.6
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            onClick?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateAppearance() {
        let text = stringValue
        var attrs = baseAttributes
        if isHovered {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attrs.removeValue(forKey: .underlineStyle)
        }
        attributedStringValue = NSAttributedString(string: text, attributes: attrs)
    }
}

/// A transparent view that covers an entire group area and responds to clicks.
/// All child labels are added as subviews of this view.
/// Set `headerLabel` to underline the project name on hover.
final class ClickableGroupView: NSView {
    var onClick: (() -> Void)?
    weak var headerLabel: NSTextField?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHeaderUnderline()
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHeaderUnderline()
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.6
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            onClick?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateHeaderUnderline() {
        guard let label = headerLabel else { return }
        let text = label.attributedStringValue
        let mutable = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: mutable.length)
        if isHovered {
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            mutable.removeAttribute(.underlineStyle, range: range)
        }
        label.attributedStringValue = mutable
    }
}
