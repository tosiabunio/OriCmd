import AppKit

/// The row of flat function key buttons at the bottom of the window
/// ("F3 View", "F4 Edit", … ), drawn as equal-width cells, with the keys as key
/// caps when so chosen in Settings. In the modern look they are hints beside the
/// command line instead: each as wide as its text, and only the keys when the
/// titles do not fit.
final class FunctionKeyBar: NSView {
    struct Item {
        let key: String
        let title: String
        let command: Command
        /// The Mac's word where Total Commander's differs ("Quit" for "Exit").
        var modernTitle: String?

        var shownTitle: String { Settings.isModern ? modernTitle ?? title : title }
    }

    static let defaultItems: [Item] = [
        Item(key: "F3", title: String(localized: "fkey.view", defaultValue: "View"), command: .list),
        Item(key: "F4", title: String(localized: "fkey.edit", defaultValue: "Edit"), command: .edit),
        Item(key: "F5", title: String(localized: "fkey.copy", defaultValue: "Copy"), command: .copy),
        Item(key: "F6", title: String(localized: "fkey.move", defaultValue: "Move"), command: .renMov),
        Item(key: "F7", title: String(localized: "fkey.newFolder", defaultValue: "NewFolder"), command: .mkDir,
             modernTitle: String(localized: "New Folder")),
        Item(key: "F8", title: String(localized: "fkey.delete", defaultValue: "Delete"), command: .delete),
        Item(key: "⌘Q", title: String(localized: "fkey.exit", defaultValue: "Exit"), command: .exit,
             modernTitle: String(localized: "Quit")),
    ]

    var items: [Item] = FunctionKeyBar.defaultItems {
        didSet { needsDisplay = true }
    }

    private var pressedIndex: Int?

    nonisolated override var isFlipped: Bool { true }
    /// Key caps get some room above and below.
    static var height: CGFloat { Settings.showsFunctionKeyCaps ? 28 : 22 }

    override var intrinsicContentSize: NSSize {
        isCompact ? NSSize(width: compactWidth(titles: true), height: 24)
            : NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    private var isCompact: Bool { Settings.isModern }

    private static let hintFont = NSFont.systemFont(ofSize: 11)
    private static let hintKeyFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let hintSpacing: CGFloat = 14

    private func hintKeyWidth(_ item: Item) -> CGFloat {
        let key = ceil((item.key as NSString).size(withAttributes: [.font: Settings.showsFunctionKeyCaps ? Self.keyCapFont : Self.hintKeyFont]).width)
        return Settings.showsFunctionKeyCaps ? max(key + 12, 22) : key
    }

    private func hintWidth(_ item: Item, titles: Bool) -> CGFloat {
        hintKeyWidth(item) + (titles ? 4 + ceil((item.shownTitle as NSString).size(withAttributes: [.font: Self.hintFont]).width) : 0)
    }

    private func compactWidth(titles: Bool) -> CGFloat {
        items.reduce(0) { $0 + hintWidth($1, titles: titles) } + Self.hintSpacing * CGFloat(max(items.count - 1, 0))
    }

    /// The hints from the right edge, with their titles if all fit.
    private var hintRects: (rects: [NSRect], titles: Bool) {
        let titles = compactWidth(titles: true) <= bounds.width + 0.5
        var x = bounds.maxX - compactWidth(titles: titles)
        let rects = items.map { item in
            let width = hintWidth(item, titles: titles)
            defer { x += width + Self.hintSpacing }
            return NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
        return (rects, titles)
    }

    private func drawHints() {
        let (rects, titles) = hintRects
        for (index, item) in items.enumerated() {
            let rect = rects[index]
            if index == pressedIndex {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: 1), xRadius: 5, yRadius: 5).fill()
            }
            let keyWidth = hintKeyWidth(item)
            if Settings.showsFunctionKeyCaps {
                drawCap(item.key, in: NSRect(x: rect.minX, y: (rect.midY - 8).rounded() + 0.5, width: keyWidth, height: 16))
            } else {
                let attributes: [NSAttributedString.Key: Any] = [.font: Self.hintKeyFont, .foregroundColor: NSColor.labelColor]
                let size = (item.key as NSString).size(withAttributes: attributes)
                (item.key as NSString).draw(at: NSPoint(x: rect.minX, y: rect.midY - size.height / 2), withAttributes: attributes)
            }
            guard titles else { continue }
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.hintFont, .foregroundColor: NSColor.secondaryLabelColor]
            let size = (item.shownTitle as NSString).size(withAttributes: attributes)
            (item.shownTitle as NSString).draw(at: NSPoint(x: rect.minX + keyWidth + 4, y: rect.midY - size.height / 2),
                                          withAttributes: attributes)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isCompact {
            drawHints()
            return
        }
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
            let label = "\(item.key) \(item.shownTitle)" as NSString
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
        let key = item.key as NSString, title = item.shownTitle as NSString
        let keySize = key.size(withAttributes: keyAttributes)
        let titleSize = title.size(withAttributes: attributes)
        let capWidth = max(ceil(keySize.width) + 14, 24), capHeight: CGFloat = 18, gap: CGFloat = 7
        let total = capWidth + gap + titleSize.width
        let x = (cell.midX - total / 2).rounded()
        let cap = NSRect(x: x, y: (cell.midY - capHeight / 2).rounded() + 0.5, width: capWidth, height: capHeight)

        drawCap(item.key, in: cap)
        title.draw(at: NSPoint(x: cap.maxX + gap, y: cell.midY - titleSize.height / 2), withAttributes: attributes)
    }

    /// A small rounded key, a little deeper at the bottom, with the key's name.
    private func drawCap(_ name: String, in cap: NSRect) {
        let path = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0), xRadius: 4, yRadius: 4)
        NSColor.quaternaryLabelColor.setFill()
        path.fill()
        NSColor.tertiaryLabelColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        NSColor.tertiaryLabelColor.setFill()
        NSRect(x: cap.minX + 2.5, y: cap.maxY - 0.5, width: cap.width - 5, height: 0.5).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.keyCapFont, .foregroundColor: NSColor.secondaryLabelColor]
        let size = (name as NSString).size(withAttributes: attributes)
        (name as NSString).draw(at: NSPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2), withAttributes: attributes)
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
        if isCompact {
            return hintRects.rects.firstIndex { $0.insetBy(dx: -Self.hintSpacing / 2, dy: 0).contains(point) }
        }
        guard bounds.contains(point), !items.isEmpty else { return nil }
        let width = bounds.width / CGFloat(items.count)
        return min(Int(point.x / width), items.count - 1)
    }
}
