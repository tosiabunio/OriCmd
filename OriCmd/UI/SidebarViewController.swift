import AppKit

/// The sidebar of the main window, as the Finder's: devices with their free space,
/// the usual folders and the directory hotlist. A click opens the place in the active
/// panel; the place of the active panel's folder stays highlighted.
final class SidebarViewController: NSViewController {
    /// A row: a section title, or a place with its icon (and a volume's free space).
    final class Node: NSObject {
        let title: String
        let url: URL?
        let icon: NSImage?
        let isVolume: Bool
        var detail = ""
        var children: [Node] = []

        init(section title: String) {
            self.title = title
            url = nil
            icon = nil
            isVolume = false
        }

        init(place url: URL, title: String, icon: NSImage, isVolume: Bool = false) {
            self.title = title
            self.url = url
            self.icon = icon
            self.isVolume = isVolume
        }
    }

    /// A place chosen: its URL, and whether it goes to the other panel.
    var onOpen: ((URL, Bool) -> Void)?
    /// The context menu of a place (the drive buttons' menu).
    var menuProvider: ((URL, Bool) -> NSMenu?)?

    private let outline = SidebarOutlineView()
    private(set) var sections: [Node] = []
    /// The location the highlight follows.
    private var revealed: URL?
    private var isRevealing = false

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("place"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .default
        outline.dataSource = self
        outline.delegate = self
        // Clicks choose places; the keys stay with the panels.
        outline.refusesFirstResponder = true
        outline.menuProvider = { [weak self] row in
            guard let self, let node = outline.item(atRow: row) as? Node, let url = node.url else { return nil }
            return menuProvider?(url, node.isVolume)
        }
        outline.setAccessibilityLabel(String(localized: "Sidebar"))

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        view = scroll

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(self, selector: #selector(placesDidChange(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(placesDidChange(_:)), name: Hotlist.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(placesDidChange(_:)),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        reload()
    }

    @objc private func placesDidChange(_ notification: Notification) {
        reload()
    }

    /// Lists the places anew; free space is measured in the background (a network
    /// volume can be slow to answer).
    func reload() {
        let devices = Node(section: String(localized: "Devices"))
        let volumes = Volume.mounted()
        devices.children = volumes.map { volume in
            Node(place: volume.url, title: volume.name, icon: DriveBar.icon(for: volume.url), isVolume: true)
        }
        let favorites = Node(section: String(localized: "Favorites"))
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let standard: [URL] = [home] + [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory,
                                        .downloadsDirectory, .applicationDirectory]
            .compactMap { manager.urls(for: $0, in: $0 == .applicationDirectory ? .localDomainMask : .userDomainMask).first }
        favorites.children = standard.filter { manager.fileExists(atPath: $0.path) }.map(place)
        #if DEBUG
        // README screenshots: the demo folders stand for the home folder and Downloads,
        // so no account name is pictured.
        if let demo = ProcessInfo.processInfo.environment["ORICMD_DEMO"], demo.hasPrefix("/") {
            let root = URL(filePath: demo)
            favorites.children = favorites.children.map { node in
                guard let url = node.url, let icon = node.icon else { return node }
                if url.path == home.path { return Node(place: root, title: "Home", icon: icon) }
                if url.lastPathComponent == "Downloads" {
                    return Node(place: root.appending(path: "Downloads"), title: node.title, icon: icon)
                }
                return node
            }
        }
        #endif
        let hotlist = Node(section: String(localized: "Hotlist"))
        hotlist.children = Hotlist.directories.map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
            .filter { manager.fileExists(atPath: $0.path) }.map(place)
        sections = [devices, favorites] + (hotlist.children.isEmpty ? [] : [hotlist])
        outline.reloadData()
        sections.forEach { outline.expandItem($0) }
        if let revealed { reveal(revealed) }

        let measured = devices.children
        Task.detached(priority: .utility) {
            let spaces = measured.map { node in node.url.flatMap { VolumeSpace(for: $0) }?.available }
            await MainActor.run { [weak self] in
                for (node, available) in zip(measured, spaces) {
                    node.detail = available.map(Settings.formattedSize) ?? ""
                }
                self?.outline.reloadData()
                self?.revealed.map { self?.reveal($0) }
            }
        }
    }

    private func place(_ url: URL) -> Node {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return Node(place: url, title: FileManager.default.displayName(atPath: url.path), icon: icon)
    }

    /// Highlights the place of `url`: a folder listed as itself, else its volume.
    func reveal(_ url: URL) {
        revealed = url
        guard isViewLoaded else { return }
        let path = url.standardizedFileURL.path
        let places = sections.dropFirst().flatMap(\.children)
        let node = places.first { $0.url?.standardizedFileURL.path == path }
            ?? sections.first?.children.filter { volume in
                let root = volume.url?.path ?? ""
                return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }.max { ($0.url?.path.count ?? 0) < ($1.url?.path.count ?? 0) }
        isRevealing = true
        defer { isRevealing = false }
        let row = node.map(outline.row(forItem:)) ?? -1
        if row >= 0 {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            outline.deselectAll(nil)
        }
    }

    /// The rows as shown, "> " before the highlighted one (for test runs).
    var rowsDescription: [String] {
        (0..<outline.numberOfRows).compactMap { row in
            guard let node = outline.item(atRow: row) as? Node else { return nil }
            let mark = outline.selectedRow == row ? "> " : "  "
            return node.url == nil ? node.title.uppercased() : mark + node.title
        }
    }

    /// Chooses the place titled `title` as a click would (for test runs).
    func pick(_ title: String) -> Bool {
        guard let row = (0..<outline.numberOfRows).first(where: { (outline.item(atRow: $0) as? Node)?.title == title }),
              let node = outline.item(atRow: row) as? Node, let url = node.url else { return false }
        onOpen?(url, false)
        return true
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? sections.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? sections[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? Node)?.url == nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? Node)?.url != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        if node.url == nil {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: node.title)
            cell.textField = label
            cell.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        let cell = PlaceCell()
        cell.show(node)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRevealing, let node = outline.item(atRow: outline.selectedRow) as? Node, let url = node.url else { return }
        onOpen?(url, false)
    }
}

/// A place: icon, name and, for a volume, its free space at the end.
private final class PlaceCell: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView = icon
        textField = title
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            detail.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ node: SidebarViewController.Node) {
        icon.image = node.icon
        title.stringValue = node.title
        detail.stringValue = node.detail
        detail.isHidden = node.detail.isEmpty
        setAccessibilityLabel(node.detail.isEmpty ? node.title : "\(node.title), \(node.detail)")
    }
}

/// The outline asks for a place's context menu by row.
private final class SidebarOutlineView: NSOutlineView {
    var menuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return row >= 0 ? menuProvider?(row) : nil
    }
}
