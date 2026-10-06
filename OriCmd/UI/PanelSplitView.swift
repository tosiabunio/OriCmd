import AppKit

/// The splitter between the panels: a hairline in the modern look, a little wider
/// in Total Commander's; either is easy to grab (`grabSlop` around it). A double
/// click splits the window evenly, as in Total Commander.
final class PanelSplitView: NSSplitView {
    var onDoubleClickDivider: (() -> Void)?

    override var dividerThickness: CGFloat { Settings.isModern ? 1 : 4 }

    /// How far beside the drawn divider the mouse still takes it.
    var grabSlop: CGFloat { Settings.isModern ? 3 : 0 }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let first = arrangedSubviews.first {
            let (at, end) = isVertical ? (point.x, first.frame.maxX) : (point.y, first.frame.maxY)
            if at >= end - grabSlop, at <= end + dividerThickness + grabSlop {
                onDoubleClickDivider?()
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// The length the panels share: the width side by side, the height one above
    /// the other (Show → Horizontal Panels).
    private var length: CGFloat { isVertical ? bounds.width : bounds.height }

    /// Puts the divider at `ratio` of the available length.
    func setRatio(_ ratio: CGFloat) {
        setPosition(((length - dividerThickness) * ratio).rounded(), ofDividerAt: 0)
    }

    var ratio: CGFloat {
        guard let first = arrangedSubviews.first, length > dividerThickness else { return 0.5 }
        return (isVertical ? first.frame.width : first.frame.height) / (length - dividerThickness)
    }
}
