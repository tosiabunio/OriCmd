import AppKit

/// One place to inspect queued jobs, live progress, and this session's results.
final class OperationsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = OperationsWindowController()
    private let table = ListTableView()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = NSButton(title: String(localized: "Cancel Operation"), target: nil, action: nil)
    private let clearButton = NSButton(title: String(localized: "Clear Finished"), target: nil, action: nil)
    private var rows: [Row] = []

    private struct Row {
        let id: UUID
        let title: String
        let source: String
        let target: String
        let status: String
        let fraction: Double?
        let canCancel: Bool
        let queued: Bool
        let error: String?
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.title = String(localized: "Operations")
        window.minSize = NSSize(width: 440, height: 280)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.rememberFrame(as: "Operations")
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(operationsDidChange(_:)), name: OperationsStore.didChange, object: nil)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        reload()
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
    }

    private func build() {
        guard let window else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("operations"))
        column.title = String(localized: "Operations")
        column.width = 620
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 92
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = false
        let list = ListBox(table)
        list.placeholder = String(localized: "No operations this session")
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        detail.lineBreakMode = .byTruncatingMiddle
        cancelButton.target = self
        cancelButton.action = #selector(cancelSelected(_:))
        clearButton.target = self
        clearButton.action = #selector(clearFinished(_:))
        let buttons = NSStackView()
        buttons.addView(clearButton, in: .leading)
        buttons.addView(cancelButton, in: .trailing)
        let root = NSView()
        window.contentView = root
        for view in [list, detail, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16).isActive = true
        }
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            list.bottomAnchor.constraint(equalTo: detail.topAnchor, constant: -8),
            detail.heightAnchor.constraint(equalToConstant: 44),
            detail.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
    }

    @objc private func operationsDidChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        reload()
    }

    private func reload() {
        let selected = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        rows = TransferQueue.shared.pending.map {
            Row(id: $0.id, title: $0.title, source: $0.source, target: $0.target,
                status: String(localized: "Queued"), fraction: nil, canCancel: true, queued: true, error: nil)
        } + OperationsStore.shared.entries.map { entry in
            let status: String
            switch entry.status {
            case .running:
                status = entry.progress.isCancelled ? String(localized: "Cancelling…") : String(localized: "Running")
            case .completed: status = String(localized: "Completed")
            case .skipped: status = String(localized: "Finished with skipped items")
            case .failed: status = String(localized: "Failed")
            case .cancelled: status = String(localized: "Cancelled")
            }
            var summary = status
            if entry.status == .running, entry.progress.totalBytes > 0 {
                let done = ByteCountFormatter.string(fromByteCount: entry.progress.doneBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: entry.progress.totalBytes, countStyle: .file)
                summary += " · " + String(localized: "\(done) of \(total)")
            } else if entry.completedItems > 0 {
                summary += " · " + String(localized: "\(entry.completedItems) completed items")
            }
            if entry.progress.skippedItems > 0 { summary += " · " + String(localized: "\(entry.progress.skippedItems) skipped items") }
            let fraction = entry.status == .running && entry.progress.totalBytes > 0
                ? min(1, max(0, Double(entry.progress.doneBytes) / Double(entry.progress.totalBytes))) : nil
            return Row(id: entry.id, title: entry.title,
                       source: entry.status == .running ? entry.progress.source : entry.source,
                       target: entry.status == .running ? entry.progress.target : entry.target,
                       status: summary, fraction: fraction,
                       canCancel: entry.status == .running && !entry.progress.isCancelled, queued: false, error: entry.error)
        }
        table.reloadData()
        if let selected, let index = rows.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateSelection()
        clearButton.isEnabled = OperationsStore.shared.entries.contains { $0.status != .running }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row]
        let heading = NSTextField(labelWithString: item.title + " · " + item.status)
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        let from = NSTextField(labelWithString: String(localized: "From: \(item.source)"))
        let to = NSTextField(labelWithString: String(localized: "To: \(item.target)"))
        for label in [from, to] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.toolTip = label.stringValue
        }
        let bar = NSProgressIndicator()
        bar.isIndeterminate = item.fraction == nil && item.canCancel && !item.queued
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = item.fraction ?? 0
        bar.isHidden = !item.canCancel || item.queued
        if bar.isIndeterminate { bar.startAnimation(nil) }
        let stack = NSStackView(views: [heading, from, to, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        for view in [heading, from, to, bar] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        }
        heading.lineBreakMode = .byTruncatingTail
        heading.toolTip = item.title + " · " + item.status
        return stack
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }
    private func updateSelection() {
        guard rows.indices.contains(table.selectedRow) else {
            cancelButton.isEnabled = false
            // An empty list says so itself.
            detail.stringValue = rows.isEmpty ? "" : String(localized: "Select an operation to inspect its result or cancel it.")
            return
        }
        let row = rows[table.selectedRow]
        cancelButton.isEnabled = row.canCancel
        detail.stringValue = row.error.map { row.status + ": " + $0 } ?? row.status + "\n" + row.source + " → " + row.target
        detail.toolTip = detail.stringValue
    }
    @objc private func cancelSelected(_ sender: Any?) {
        guard rows.indices.contains(table.selectedRow) else { return }
        let row = rows[table.selectedRow]
        if row.queued { TransferQueue.shared.cancel(row.id) }
        else { OperationsStore.shared.cancel(row.id) }
    }
    @objc private func clearFinished(_ sender: Any?) { OperationsStore.shared.clearFinished() }
}
