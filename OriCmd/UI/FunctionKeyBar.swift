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

    /// The modifier keys held: the bar then shows what the function keys do with them
    /// (⇧F5 Copy Here, ⌃F3 Name…), as Total Commander's does.
    var modifiers: NSEvent.ModifierFlags = [] {
        didSet {
            guard modifiers != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// The keys shown: those of the modifiers held when some function key has a
    /// command with them, the plain ones otherwise.
    var shownItems: [Item] {
        guard !modifiers.isEmpty else { return items }
        let variants = Self.items(for: modifiers)
        return variants.isEmpty ? items : variants
    }

    /// The commands whose key is a function key with exactly `modifiers`, in the keys'
    /// order, as their current key bindings have them.
    static func items(for modifiers: NSEvent.ModifierFlags) -> [Item] {
        let held = modifiers.intersection(Self.modifierKeys)
        return Command.allCases.compactMap { command -> (Int, Item)? in
            guard let shortcut = KeyBindings.shortcut(for: command),
                  shortcut.modifiers.intersection(Self.modifierKeys) == held,
                  shortcut.key.unicodeScalars.count == 1, let scalar = shortcut.key.unicodeScalars.first,
                  case let number = Int(scalar.value) - NSF1FunctionKey + 1, (1...12).contains(number) else { return nil }
            return (number, Item(key: shortcut.displayText, title: command.hintTitle, command: command))
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    private static let modifierKeys: NSEvent.ModifierFlags = [.shift, .option, .control, .command]
    private var flagsMonitor: Any?

    /// Follows the modifier keys while the window is key; letting go of the window
    /// lets go of them.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        // Not while typing (in the command line, a dialog's field): Shift for a capital
        // letter would change the keys under the text.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self, let window = self.window, event.window === window {
                self.modifiers = window.firstResponder is NSText ? [] : event.modifierFlags.intersection(Self.modifierKeys)
            }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)),
                                               name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        modifiers = []
    }

    private var pressedIndex: Int?

    nonisolated override var isFlipped: Bool { true }
    /// Key caps get some room above and below.
    static var height: CGFloat { Settings.showsFunctionKeyCaps ? 28 : 22 }

    override var intrinsicContentSize: NSSize {
        // As wide as the plain keys at least, so holding a modifier does not move the command line.
        isCompact ? NSSize(width: max(compactWidth(of: items, titles: true), compactWidth(titles: true)), height: Self.compactHeight)
            : NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    private var isCompact: Bool { Settings.isModern }

    /// The hints follow the panel header's detail size: 11 pt for a 13 pt list.
    private static var hintFont: NSFont { Theme.headerDetailFont }
    private static var hintKeyFont: NSFont { .systemFont(ofSize: Theme.headerDetailFont.pointSize, weight: .semibold) }
    /// A hint's key cap, and the hints' height: 16 and 24 pt for a 13 pt list.
    private static var hintCapHeight: CGFloat { Theme.lineHeight(keyCapFont) + 4 }
    static var compactHeight: CGFloat { max(24, hintCapHeight + 8) }
    private static let hintSpacing: CGFloat = 14

    private func hintKeyWidth(_ item: Item) -> CGFloat {
        let key = ceil((item.key as NSString).size(withAttributes: [.font: Settings.showsFunctionKeyCaps ? Self.keyCapFont : Self.hintKeyFont]).width)
        return Settings.showsFunctionKeyCaps ? max(key + 12, Self.hintCapHeight + 6) : key
    }

    private func hintWidth(_ item: Item, titles: Bool) -> CGFloat {
        hintKeyWidth(item) + (titles ? 4 + ceil((item.shownTitle as NSString).size(withAttributes: [.font: Self.hintFont]).width) : 0)
    }

    private func compactWidth(titles: Bool) -> CGFloat {
        compactWidth(of: shownItems, titles: titles)
    }

    private func compactWidth(of items: [Item], titles: Bool) -> CGFloat {
        items.reduce(0) { $0 + hintWidth($1, titles: titles) } + Self.hintSpacing * CGFloat(max(items.count - 1, 0))
    }

    /// The hints from the right edge, with their titles if all fit.
    private var hintRects: (rects: [NSRect], titles: Bool) {
        let titles = compactWidth(titles: true) <= bounds.width + 0.5
        var x = bounds.maxX - compactWidth(titles: titles)
        let rects = shownItems.map { item in
            let width = hintWidth(item, titles: titles)
            defer { x += width + Self.hintSpacing }
            return NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
        return (rects, titles)
    }

    private func drawHints() {
        let (rects, titles) = hintRects
        for (index, item) in shownItems.enumerated() {
            let rect = rects[index]
            if index == pressedIndex {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: 1), xRadius: 5, yRadius: 5).fill()
            }
            let keyWidth = hintKeyWidth(item)
            if Settings.showsFunctionKeyCaps {
                let height = Self.hintCapHeight
                drawCap(item.key, in: NSRect(x: rect.minX, y: (rect.midY - height / 2).rounded() + 0.5, width: keyWidth, height: height))
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
        for (index, item) in shownItems.enumerated() {
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

    /// 10 pt, and in the modern look a point under the hints'.
    private static var keyCapFont: NSFont {
        .monospacedDigitSystemFont(ofSize: Settings.isModern ? Theme.headerDetailFont.pointSize - 1 : 10, weight: .medium)
    }

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
            shownItems[released].command.send(from: self)
        }
    }

    private func cellRect(at index: Int) -> NSRect {
        let width = bounds.width / CGFloat(max(shownItems.count, 1))
        let minX = (CGFloat(index) * width).rounded()
        let maxX = (CGFloat(index + 1) * width).rounded()
        return NSRect(x: minX, y: 0, width: maxX - minX, height: bounds.height)
    }

    private func index(at point: NSPoint) -> Int? {
        if isCompact {
            return hintRects.rects.firstIndex { $0.insetBy(dx: -Self.hintSpacing / 2, dy: 0).contains(point) }
        }
        let items = shownItems
        guard bounds.contains(point), !items.isEmpty else { return nil }
        let width = bounds.width / CGFloat(items.count)
        return min(Int(point.x / width), items.count - 1)
    }
}

private extension Command {
    /// A word or two for the key bar, where the menu's title is too long.
    var hintTitle: String {
        switch self {
        case .compareDirs: String(localized: "Compare")
        case .editNewFile: String(localized: "New File")
        case .copySamePanel: String(localized: "Copy Here")
        case .renameOnly: String(localized: "Rename")
        case .deletePermanently: String(localized: "Delete Now")
        case .createSymlink: String(localized: "Link")
        case .packFiles: String(localized: "Pack")
        case .unpackFiles: String(localized: "Unpack")
        case .testArchive: String(localized: "Test")
        case .sortByName: String(localized: "Name")
        case .sortByExt: String(localized: "Ext")
        case .sortByDateTime: String(localized: "Date")
        case .sortBySize: String(localized: "Size")
        case .unsorted: String(localized: "Unsorted")
        case .cdTree: String(localized: "Tree")
        case .leftOpenDrives: String(localized: "Left Drive")
        case .rightOpenDrives: String(localized: "Right Drive")
        case .searchFor: String(localized: "Find")
        default:
            String(title.split(separator: "  ").first ?? Substring(title)).replacingOccurrences(of: "…", with: "")
        }
    }
}
