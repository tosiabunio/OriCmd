import AppKit

/// The row of flat function key buttons at the bottom of the window
/// ("F3 View", "F4 Edit", … ), drawn as equal-width cells, with the keys as key
/// caps when so chosen in Settings.
final class FunctionKeyBar: NSView {
    struct Item {
        let key: String
        let title: String
        let command: Command
    }

    static let defaultItems: [Item] = [
        Item(key: "F3", title: String(localized: "fkey.view", defaultValue: "View"), command: .list),
        Item(key: "F4", title: String(localized: "fkey.edit", defaultValue: "Edit"), command: .edit),
        Item(key: "F5", title: String(localized: "fkey.copy", defaultValue: "Copy"), command: .copy),
        Item(key: "F6", title: String(localized: "fkey.move", defaultValue: "Move"), command: .renMov),
        Item(key: "F7", title: String(localized: "fkey.newFolder", defaultValue: "NewFolder"), command: .mkDir),
        Item(key: "F8", title: String(localized: "fkey.delete", defaultValue: "Delete"), command: .delete),
        Item(key: "⌘Q", title: String(localized: "fkey.exit", defaultValue: "Exit"), command: .exit),
    ]

    var items: [Item] = FunctionKeyBar.defaultItems {
        didSet { needsDisplay = true }
    }

    private var pressedIndex: Int?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chromeBackground.setFill()
        bounds.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.chromeFont,
            .foregroundColor: Theme.chromeText,
        ]
        let keyCaps = Settings.showsFunctionKeyCaps
        for (index, item) in items.enumerated() {
            let cell = cellRect(at: index)
            if index == pressedIndex {
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                cell.fill()
            }
            if keyCaps {
                drawKeyCap(item, in: cell, attributes: attributes)
                continue
            }
            let label = "\(item.key) \(item.title)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2),
                withAttributes: attributes
            )
            if index > 0 {
                Theme.separator.setFill()
                NSRect(x: cell.minX, y: cell.minY + 3, width: 1, height: cell.height - 6).fill()
            }
        }
        Theme.separator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    private static let keyCapFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)

    /// The key in a small rounded key, then the title, both centred in the cell.
    private func drawKeyCap(_ item: Item, in cell: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.keyCapFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let key = item.key as NSString, title = item.title as NSString
        let keySize = key.size(withAttributes: keyAttributes)
        let titleSize = title.size(withAttributes: attributes)
        let capWidth = max(ceil(keySize.width) + 8, 18), capHeight: CGFloat = 15, gap: CGFloat = 5
        let total = capWidth + gap + titleSize.width
        let x = (cell.midX - total / 2).rounded()
        let cap = NSRect(x: x, y: (cell.midY - capHeight / 2).rounded() + 0.5, width: capWidth, height: capHeight)

        let path = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0), xRadius: 3.5, yRadius: 3.5)
        NSColor.quaternaryLabelColor.setFill()
        path.fill()
        NSColor.tertiaryLabelColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        // Key caps are a little deeper at the bottom.
        NSColor.tertiaryLabelColor.setFill()
        NSRect(x: cap.minX + 2.5, y: cap.maxY - 0.5, width: cap.width - 5, height: 0.5).fill()

        key.draw(at: NSPoint(x: cap.midX - keySize.width / 2, y: cap.midY - keySize.height / 2), withAttributes: keyAttributes)
        title.draw(at: NSPoint(x: cap.maxX + gap, y: cell.midY - titleSize.height / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        pressedIndex = index(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let current = index(at: convert(event.locationInWindow, from: nil))
        if current != pressedIndex {
            pressedIndex = current
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let released = index(at: convert(event.locationInWindow, from: nil))
        let pressed = pressedIndex
        pressedIndex = nil
        needsDisplay = true
        if let released, released == pressed {
            items[released].command.send(from: self)
        }
    }

    private func cellRect(at index: Int) -> NSRect {
        let width = bounds.width / CGFloat(max(items.count, 1))
        let minX = (CGFloat(index) * width).rounded()
        let maxX = (CGFloat(index + 1) * width).rounded()
        return NSRect(x: minX, y: 0, width: maxX - minX, height: bounds.height)
    }

    private func index(at point: NSPoint) -> Int? {
        guard bounds.contains(point), !items.isEmpty else { return nil }
        let width = bounds.width / CGFloat(items.count)
        return min(Int(point.x / width), items.count - 1)
    }
}
