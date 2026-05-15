import AppKit

/// A view that passes mouse events through to the windows behind it,
/// except for ClickableLabel subviews which handle their own clicks.
final class ClickThroughView: NSVisualEffectView {
    /// When true, the entire view is interactive (used during move mode).
    var interactiveMode = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        // During move mode, the whole view is draggable
        if interactiveMode {
            return super.hitTest(point)
        }

        // Otherwise, only ClickableLabel instances are interactive
        guard let hit = super.hitTest(point) else { return nil }

        if hit is ClickableLabel || hit is ClickableGroupView {
            return hit
        }

        // Walk up in case the hit is a subview of a clickable view
        var current: NSView? = hit
        while let parent = current?.superview {
            if parent is ClickableLabel || parent is ClickableGroupView {
                return parent
            }
            if parent === self { break }
            current = parent
        }

        // Not a clickable element — pass through
        return nil
    }
}
