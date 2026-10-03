import AppKit

/// File rows are accessibility elements even though the panel draws them itself.
extension FileListView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { String(localized: "Files") }
    override func accessibilityRowCount() -> Int { items.count }

    override func accessibilityChildren() -> [Any]? {
        accessibilityFileRows() + (super.accessibilityChildren() ?? [])
    }

    override func accessibilityRows() -> [Any]? { accessibilityFileRows() }

    override func accessibilityVisibleChildren() -> [Any]? {
        accessibilityFileRows().filter { rowRect($0.index).intersects(visibleRect) }
    }

    override func accessibilitySelectedRows() -> [Any]? {
        accessibilityFileRows().filter { $0.isAccessibilitySelected() }
    }

    override func accessibilitySelectedChildren() -> [Any]? { accessibilitySelectedRows() }

    override func setAccessibilitySelectedRows(_ rows: [Any]?) {
        let selected = (rows ?? []).compactMap { $0 as? FileAccessibilityRow }
            .filter { $0.list === self && $0.isCurrent }
        guard let first = selected.first else { setMarked([]); return }
        window?.makeFirstResponder(self)
        moveCursor(to: first.index)
        setMarked(selected.count == 1 ? [] : Set(selected.compactMap { $0.item?.isParent == false ? $0.item?.name : nil }))
    }

    nonisolated override var accessibilityFocusedUIElement: Any? {
        let row: FileAccessibilityRow? = MainActor.assumeIsolated {
            guard window?.firstResponder === self else { return nil }
            return accessibilityFileRows().first { $0.index == cursor }
        }
        return row ?? self
    }

    nonisolated override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        let row: FileAccessibilityRow? = MainActor.assumeIsolated {
            guard let window else { return nil }
            let local = convert(window.convertPoint(fromScreen: point), from: nil)
            return index(at: local).map { accessibilityFileRows()[$0] }
        }
        return row ?? self
    }

    /// Rows are made only when requested, and keep their identity across refreshes.
    func accessibilityFileRows() -> [FileAccessibilityRow] {
        if let fileAccessibilityRows { return fileAccessibilityRows }
        fileAccessibilityRows = items.enumerated().map { FileAccessibilityRow(list: self, item: $0.element, index: $0.offset) }
        return fileAccessibilityRows ?? []
    }

    func reloadAccessibilityRows() {
        if let rows = fileAccessibilityRows {
            let previous = Dictionary(rows.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
            fileAccessibilityRows = items.enumerated().map { index, item in
                let row = previous[FileAccessibilityRow.identity(of: item)] ?? FileAccessibilityRow(list: self, item: item, index: index)
                row.index = index
                return row
            }
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
        accessibilitySelectionChanged()
    }

    func accessibilitySelectionChanged() {
        NSAccessibility.post(element: self, notification: .selectedRowsChanged)
        if let row = fileAccessibilityRows?.first(where: { $0.index == cursor }), window?.firstResponder === self {
            NSAccessibility.post(element: row, notification: .focusedUIElementChanged)
        }
    }
}

/// Uses the panel's current data and geometry, including Brief and Thumbnails views.
nonisolated final class FileAccessibilityRow: NSAccessibilityElement, @unchecked Sendable {
    @MainActor weak var list: FileListView?
    let identity: String
    @MainActor var index: Int

    @MainActor init(list: FileListView, item: FileItem, index: Int) {
        self.list = list
        identity = Self.identity(of: item)
        self.index = index
        super.init()
        setAccessibilityParent(list)
    }

    static func identity(of item: FileItem) -> String { item.url.absoluteString + "\0" + item.name }

    @MainActor var item: FileItem? {
        guard let list, list.items.indices.contains(index), Self.identity(of: list.items[index]) == identity else { return nil }
        return list.items[index]
    }

    @MainActor var isCurrent: Bool { item != nil }
    // AppKit invokes these callbacks on the main thread. An explicit concrete
    // capture bridges its nonisolated NSObject APIs to the panel's main actor.
    nonisolated private func onMain<T: Sendable>(_ body: @MainActor @Sendable (FileAccessibilityRow) -> T) -> T {
        nonisolated(unsafe) let element: AnyObject = self
        return MainActor.assumeIsolated { body(element as! FileAccessibilityRow) }
    }

    override func isAccessibilityElement() -> Bool {
        onMain { row in row.isCurrent }
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }
    override func accessibilityIndex() -> Int {
        onMain { row in row.index }
    }
    override func accessibilityLabel() -> String? {
        onMain { row in
            guard let item = row.item else { return nil }
            return item.isParent ? String(localized: "Parent folder") : item.name
        }
    }

    override func accessibilityValue() -> Any? {
        let value: String? = onMain { row in
            guard let item = row.item, !item.isParent else { return nil }
            let kind = item.isSymlink ? String(localized: "Symbolic link")
                : (item.isDirectory ? String(localized: "Folder") : String(localized: "File"))
            let size = item.isDirectory ? "" : Settings.formattedSize(item.size)
            return [kind, size, item.modified.formatted(date: .numeric, time: .shortened)]
                .filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return value
    }

    override func accessibilityFrame() -> NSRect {
        onMain { row in
            guard let list = row.list, let window = list.window, row.isCurrent else { return .zero }
            return window.convertToScreen(list.convert(list.rowRect(row.index), to: nil))
        }
    }

    override func isAccessibilitySelected() -> Bool {
        onMain { row in
            guard let list = row.list, let item = row.item else { return false }
            return list.marked.isEmpty ? list.cursor == row.index : list.marked.contains(item.name)
        }
    }

    override func isAccessibilityFocused() -> Bool {
        onMain { row in
            guard let list = row.list else { return false }
            return row.isCurrent && list.window?.firstResponder === list && list.cursor == row.index
        }
    }

    override func setAccessibilityFocused(_ focused: Bool) {
        onMain { row in
            guard focused, let list = row.list, row.isCurrent else { return }
            list.window?.makeFirstResponder(list)
            list.moveCursor(to: row.index)
        }
    }

    override func accessibilityPerformPick() -> Bool {
        onMain { row in
            guard let list = row.list, row.isCurrent else { return false }
            list.setAccessibilitySelectedRows([row])
            return true
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onMain { row in
            guard row.accessibilityPerformPick(), let list = row.list else { return false }
            list.delegate?.fileList(list, openItemAt: row.index)
            return true
        }
    }

    override func accessibilityPerformShowMenu() -> Bool {
        onMain { row in
            guard let list = row.list, let item = row.item else { return false }
            if !list.marked.contains(item.name) { list.setMarked([]) }
            list.window?.makeFirstResponder(list)
            list.moveCursor(to: row.index)
            guard let menu = list.delegate?.fileList(list, contextMenuFor: list.selectedEntries) else { return false }
            menu.popUp(positioning: nil,
                       at: NSPoint(x: list.rowRect(row.index).minX + 20, y: list.rowRect(row.index).maxY), in: list)
            return true
        }
    }
}
