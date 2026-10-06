import AppKit

/// Column titles above the file list. Clicking a title sorts by that column,
/// clicking it again reverses the order; right click chooses optional columns.
/// Dragging the edge between two titles resizes a column, a double click on it
/// gives the column its measured width again.
final class FileListHeaderView: NSView {
    static let titles: [SortColumn: String] = [
        .name: String(localized: "Name"), .ext: String(localized: "Ext"), .size: String(localized: "Size"),
        .date: String(localized: "Date"), .attr: String(localized: "Attr"), .kind: String(localized: "Kind"),
        .created: String(localized: "Created"), .dimensions: String(localized: "Dimensions"),
        .duration: String(localized: "Duration"), .tags: String(localized: "Tags"),
        .comment: String(localized: "Comment"),
    ]

    /// The columns after Name, and the column set they come from ("" the Default view).
    var columns = ColumnSet.standard {
        didSet { if columns != oldValue { needsDisplay = true } }
    }
    var columnSet = ""
    /// A column set chosen in the menu ("" the Default view).
    var onChooseColumnSet: ((String) -> Void)?

    var sortOrder = SortOrder() {
        didSet { needsDisplay = true }
    }

    var onColumnClicked: ((SortColumn) -> Void)?

    /// The title under the mouse, and the one held down.
    private var hovered: SortColumn? {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    private var pressed: SortColumn? {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }

    nonisolated override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }
    static var height: CGFloat { Settings.isModern ? 22 : 18 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self, selector: #selector(columnWidthsDidChange(_:)),
                                               name: ColumnLayout.widthsDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func columnWidthsDidChange(_ notification: Notification) {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// The columns as the list below lays them out: inside its border in Total
    /// Commander's look, inset as its rows in the modern one.
    private var layout: ColumnLayout {
        ColumnLayout(width: bounds.width, columns: columns, inset: Settings.isModern ? Theme.contentInset : 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let modern = Settings.isModern
        (modern ? Theme.panelBackground : Theme.chromeBackground).setFill()
        bounds.fill()

        let layout = layout
        for column in layout.columns {
            let cell = layout.rect(for: column, y: 0, height: bounds.height)
            let sorted = column == sortOrder.column && !sortOrder.isUnsorted
            if column == pressed {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: cell.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4).fill()
            }
            if modern {
                drawModernTitle(column, in: cell, sorted: sorted)
            } else {
                var title = Self.titles[column]!
                if sorted {
                    title += sortOrder.ascending ? " ▴" : " ▾"
                }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: Theme.chromeFont,
                    .foregroundColor: column == hovered ? NSColor.labelColor : Theme.chromeText,
                ]
                let size = (title as NSString).size(withAttributes: attributes)
                (title as NSString).draw(
                    at: NSPoint(x: cell.minX + 4, y: (bounds.height - size.height) / 2),
                    withAttributes: attributes
                )
                Theme.separator.setFill()
                NSRect(x: cell.maxX - 1, y: 2, width: 1, height: bounds.height - 4).fill()
            }
        }
        Theme.separator.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    /// No separators; the sorted column in semibold with a chevron, Size aligned
    /// right as its values are.
    private func drawModernTitle(_ column: SortColumn, in cell: NSRect, sorted: Bool) {
        let font = sorted ? NSFont.systemFont(ofSize: 11, weight: .semibold) : Theme.chromeFont
        let color = sorted || column == hovered ? NSColor.labelColor : NSColor.secondaryLabelColor
        let title = Self.titles[column]!
        let size = (title as NSString).size(withAttributes: [.font: font])
        let chevron: NSImage? = sorted ? NSImage(systemSymbolName: sortOrder.ascending ? "chevron.up" : "chevron.down",
                                                 accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))) : nil
        let chevronWidth = chevron.map { $0.size.width + 4 } ?? 0
        let width = min(size.width, cell.width - 8 - chevronWidth)
        let x = column == .size ? cell.maxX - 4 - width - chevronWidth : cell.minX + 4
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(with: NSRect(x: x, y: (bounds.height - size.height) / 2, width: width, height: size.height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        if let chevron {
            chevron.draw(in: NSRect(x: x + width + 4, y: (bounds.height - chevron.size.height) / 2,
                                    width: chevron.size.width, height: chevron.size.height))
        }
    }

    /// Where the edge right of a column is, and the middle of its title (for test runs).
    func edgeX(of column: SortColumn) -> CGFloat? {
        let layout = layout
        return layout.contains(column) ? layout.rect(for: column, y: 0, height: 0).maxX : nil
    }

    func titleX(of column: SortColumn) -> CGFloat? {
        let layout = layout
        return layout.contains(column) ? layout.rect(for: column, y: 0, height: 0).midX : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let layout = layout
        hovered = layout.resizableEdge(near: x) == nil ? layout.column(at: x) : nil
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
    }

    override func resetCursorRects() {
        let layout = layout
        for column in layout.columns.dropLast() {
            let cell = layout.rect(for: column, y: 0, height: bounds.height)
            addCursorRect(NSRect(x: cell.maxX - 3, y: 0, width: 6, height: bounds.height), cursor: .resizeLeftRight)
        }
    }

    /// Right click: the columns of the set shown (changed for every panel using
    /// it), and the column sets to choose from.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for column in SortColumn.optional {
            let item = NSMenuItem(title: Self.titles[column] ?? "", action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.rawValue
            item.state = columns.contains(column) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for name in [""] + ColumnSet.saved.map(\.name) {
            let item = NSMenuItem(title: name.isEmpty ? String(localized: "Default Columns") : name,
                                  action: #selector(chooseSet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == columnSet ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem(title: String(localized: "Column Sets…"),
                                action: #selector(MainViewController.configureColumnSets(_:)), keyEquivalent: ""))
        return menu
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let column = SortColumn(rawValue: raw) else { return }
        var changed = columns
        if let index = changed.firstIndex(of: column) {
            changed.remove(at: index)
        } else {
            changed.append(column)
        }
        ColumnSet.setColumns(changed, of: columnSet)
    }

    @objc private func chooseSet(_ sender: NSMenuItem) {
        onChooseColumnSet?(sender.representedObject as? String ?? "")
    }

    /// A click on a title sorts; on an edge between titles, a drag resizes and a
    /// double click gives back the measured width.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let layout = layout
        if let edge = layout.resizableEdge(near: point.x) {
            if event.clickCount == 2 {
                ColumnLayout.customWidths[edge.column] = nil
                ColumnLayout.saveCustomWidths()
            } else {
                resize(edge, in: layout, from: event)
            }
            return
        }
        guard let column = layout.column(at: point.x) else { return }
        pressed = column
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]), next.type != .leftMouseUp {
            pressed = layout.column(at: convert(next.locationInWindow, from: nil).x) == column ? column : nil
        }
        if pressed == column {
            onColumnClicked?(column)
        }
        pressed = nil
    }

    /// Follows the mouse until it is let go: the column grows or shrinks, Name takes
    /// or gives the difference (never below its minimum).
    private func resize(_ edge: (column: SortColumn, sign: CGFloat, x: CGFloat), in layout: ColumnLayout, from event: NSEvent) {
        let start = layout.rect(for: edge.column, y: 0, height: 0).width
        let most = start + layout.nameWidth - ColumnLayout.minimumNameWidth
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let x = convert(next.locationInWindow, from: nil).x
            let width = (start + edge.sign * (x - edge.x)).rounded()
            ColumnLayout.customWidths[edge.column] = min(max(width, ColumnLayout.minimumColumnWidth), max(most, start))
            if next.type == .leftMouseUp { break }
        }
        ColumnLayout.saveCustomWidths()
    }
}
