import AppKit

/// Total Commander's F5 / F6 dialog: the target with a name mask ("*.*"),
/// "Only files of this type", Verify, one row of buttons (Copy or Move, F2 Queue, Tree,
/// Cancel, Options >>) and, under Options, the overwrite mode and more. The modern look
/// names what is copied beside its icon, leaves the mask out of the target until one is
/// typed and shows the list buttons as symbols.
///
/// Keys: Return confirms, F2 queue, F7 adds/removes the target in the target list,
/// F8 filter menu, ⌃D directory hotlist, Esc cancels. Right click on OK or
/// F2 Queue switches between copying and moving.
final class CopyDialog: NSObject {
    struct Result {
        var kind: TransferJob.Kind
        var target: String
        var options: TransferOptions
        var queued: Bool
        var toAllSelectedFolders: Bool
    }

    private static var current: CopyDialog?

    private enum Key {
        static let targetList = "CopyTargetList"
        static let targetHistory = "CopyTargetHistory"
        static let filterList = "CopyFilterList"
        static let filterHistory = "CopyFilterHistory"
        static let pinned = "CopyOptionsPinned"
    }

    private static let historyLimit = 15
    private static let buttonWidth: CGFloat = 112

    private let kind: TransferJob.Kind
    private let completion: (Result) -> Void
    private let panel = CopyDialogPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
                                        styleMask: [.titled], backing: .buffered, defer: true)
    private weak var parent: NSWindow?

    private let targetBox = NSComboBox()
    private let targetListButton = NSButton(title: "+ F7", target: nil, action: nil)
    private let filterBox = NSComboBox()
    private let filterButton = NSButton(title: "+ F8", target: nil, action: nil)
    private let attributesBox = NSButton(checkboxWithTitle: String(localized: "Copy extended attributes and ACLs"),
                                         target: nil, action: nil)
    private let verifyBox = NSButton(checkboxWithTitle: String(localized: "Verify"), target: nil, action: nil)
    private let okButton = NSButton(title: String(localized: "OK"), target: nil, action: nil)
    private let queueButton = NSButton(title: String(localized: "F2 Queue"), target: nil, action: nil)
    private let optionsButton = NSButton(title: String(localized: "Options >>"), target: nil, action: nil)
    private let optionsSummary = NSTextField(wrappingLabelWithString: "")
    private let advanced = NSBox()
    private let pinButton = NSButton()
    private let overwritePopUp = NSPopUpButton()
    private let saveButton = NSButton()
    private let skipUnreadableBox = NSButton(checkboxWithTitle: String(localized: "Skip all which cannot be opened for reading"),
                                             target: nil, action: nil)
    private let overwriteLockedBox = NSButton(checkboxWithTitle: String(localized: "Overwrite/delete locked files"),
                                              target: nil, action: nil)
    private let skipDSStoreBox = NSButton(checkboxWithTitle: String(localized: "Skip .DS_Store (Finder\u{2019}s folder view settings)"),
                                          target: nil, action: nil)
    private let allFoldersBox = NSButton(checkboxWithTitle: String(localized: "Copy to all selected folders in the target panel"),
                                         target: nil, action: nil)

    /// Shows the dialog as a sheet of `window`. `target` is the folder (ending in "/");
    /// `selectedTargetFolders` is the number of folders marked in the target panel.
    static func show(kind: TransferJob.Kind, files: Int, folders: Int, source: String, items: [URL], marked: Bool,
                     target: String, selectedTargetFolders: Int,
                     in window: NSWindow, completion: @escaping (Result) -> Void) {
        let dialog = CopyDialog(kind: kind, completion: completion)
        current = dialog
        dialog.present(files: files, folders: folders, source: source, items: items, marked: marked,
                       target: target, selectedTargetFolders: selectedTargetFolders,
                       in: window)
    }

    /// The name mask a target folder gets: Total Commander's "*.*", none in the modern look.
    private static var mask: String { Settings.isModern ? "" : "*.*" }

    private init(kind: TransferJob.Kind, completion: @escaping (Result) -> Void) {
        self.kind = kind
        self.completion = completion
        super.init()
    }

    // MARK: - Layout

    private func present(files: Int, folders: Int, source: String, items: [URL], marked: Bool,
                         target: String, selectedTargetFolders: Int, in window: NSWindow) {
        parent = window
        let modern = Settings.isModern
        let names = items.map(\.lastPathComponent)
        let message = NSTextField(labelWithString: kind == .copy
            ? String(localized: "copy.button", defaultValue: "Copy") : String(localized: "move.button", defaultValue: "Move"))
        message.font = .boldSystemFont(ofSize: 15)
        var counts: [String] = []
        if files > 0 { counts.append(String(localized: "\(files) files")) }
        if folders > 0 { counts.append(String(localized: "\(folders) folders")) }
        let scope = marked ? String(localized: "Marked selection") : String(localized: "Item under cursor")
        let selection = NSTextField(labelWithString: scope + " · " + counts.joined(separator: ", "))
        let previewLabel = NSTextField(labelWithString: Prompt.names(names))
        previewLabel.lineBreakMode = .byTruncatingMiddle
        previewLabel.toolTip = names.joined(separator: "\n")
        let from = NSTextField(labelWithString: String(localized: "From: \(source)"))
        from.lineBreakMode = .byTruncatingMiddle
        from.toolTip = source
        from.isSelectable = true
        from.textColor = .secondaryLabelColor
        optionsSummary.textColor = .secondaryLabelColor
        optionsSummary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        targetBox.stringValue = target + Self.mask
        targetBox.completes = false
        targetBox.numberOfVisibleItems = 12
        targetBox.delegate = self
        targetListButton.target = self
        targetListButton.action = #selector(toggleTargetList(_:))
        targetListButton.keyEquivalent = Self.functionKey(7)
        targetListButton.toolTip = String(localized: "Add the target to the target list, or remove it (F7). ⌃D: directory hotlist")
        filterBox.delegate = self
        filterBox.completes = false
        filterBox.numberOfVisibleItems = 12
        filterButton.target = self
        filterButton.action = #selector(showFilterMenu(_:))
        filterButton.keyEquivalent = Self.functionKey(8)
        filterButton.toolTip = String(localized: "Saved filters and examples (F8)")
        if modern {
            filterButton.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: nil)
            filterButton.title = String(localized: "Filters")
            filterBox.placeholderString = String(localized: "All files")
        }
        for button in [targetListButton, filterButton] {
            if modern { button.imagePosition = .imageOnly }
            button.widthAnchor.constraint(equalToConstant: modern ? 36 : 58).isActive = true
            // They have F7 / F8; Tab goes straight from the target to the filter.
            button.refusesFirstResponder = true
        }
        reloadTargetItems()
        reloadFilterItems()

        let store = AppDefaults.store
        attributesBox.state = Settings.copyAttributes ? .on : .off
        verifyBox.state = Settings.copyVerifies ? .on : .off

        okButton.title = message.stringValue
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        queueButton.keyEquivalent = Self.functionKey(2)
        let treeButton = NSButton(title: String(localized: "Tree"), target: self, action: #selector(chooseFolder(_:)))
        okButton.target = self
        okButton.action = #selector(confirm(_:))
        queueButton.target = self
        queueButton.action = #selector(confirm(_:))
        optionsButton.target = self
        optionsButton.action = #selector(expand(_:))
        for button in [okButton, queueButton] {
            button.menu = switchMenu()
        }
        let buttons = [okButton, queueButton, treeButton, cancelButton, optionsButton]
        for button in buttons {
            // The modern look sizes them to their titles, as Mac dialogs do.
            if modern {
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
            } else {
                button.widthAnchor.constraint(equalToConstant: Self.buttonWidth).isActive = true
            }
        }
        if modern {
            optionsButton.title = String(localized: "Options")
            optionsButton.imagePosition = .imageTrailing
            queueButton.title = String(localized: "Queue")
            queueButton.toolTip = String(localized: "Add to the queue of operations (F2)")
            treeButton.title = String(localized: "Choose…")
        }
        // As in Mac dialogs: the default button last on the right, Cancel before it and
        // the queue beside them; the other actions at the left.
        let gap = NSView()
        gap.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttonRow = NSStackView(views: [optionsButton, treeButton, gap, queueButton, cancelButton, okButton])
        buttonRow.spacing = 8
        buttonRow.setCustomSpacing(0, after: gap)

        buildAdvanced(selectedTargetFolders: selectedTargetFolders)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = modern
            ? [heading(counts: counts.joined(separator: ", "), items: items, preview: previewLabel, from: from)]
            : [message, selection, previewLabel, from]
        let stack = NSStackView(views: header + [
            NSTextField(labelWithString: String(localized: "To:")),
            row(targetBox, targetListButton),
            NSTextField(labelWithString: String(localized: "Only files of this type:")),
            row(filterBox, filterButton),
            row(attributesBox, spacer, verifyBox),
            optionsSummary,
            buttonRow,
            advanced,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: optionsSummary)
        if modern, let heading = header.first { stack.setCustomSpacing(16, after: heading) }
        stack.setCustomSpacing(14, after: buttonRow)
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 18, right: 20)
        for view in stack.arrangedSubviews where view !== message {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: 5 * Self.buttonWidth + 4 * 8 + 40).isActive = true

        panel.contentView = stack
        panel.defaultButtonCell = okButton.cell as? NSButtonCell
        panel.initialFirstResponder = targetBox
        panel.autorecalculatesKeyViewLoop = true
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        advanced.isHidden = !store.bool(forKey: Key.pinned)
        if modern {
            updateOptionsButton()
        } else {
            optionsButton.isHidden = !advanced.isHidden
        }
        panel.setContentSize(stack.fittingSize)

        updateOptionsSummary()
        window.beginSheet(panel)
        DispatchQueue.main.async { [targetBox] in
            targetBox.currentEditor()?.selectAll(nil)
        }
    }

    /// The modern look's top: the icon of what is copied, "Copy “name”" or "Copy 3 files"
    /// (`counts`) beside it, the names of several under it and the folder they come from.
    private func heading(counts: String, items: [URL], preview: NSTextField, from: NSTextField) -> NSView {
        let icon = NSImageView(image: FileIcons.icon(for: items))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let title: String
        if items.count == 1 {
            let name = items[0].lastPathComponent
            title = kind == .copy ? String(localized: "Copy \u{201C}\(name)\u{201D}") : String(localized: "Move \u{201C}\(name)\u{201D}")
        } else {
            title = kind == .copy ? String(localized: "Copy \(counts)") : String(localized: "Move \(counts)")
        }
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.textColor = .secondaryLabelColor
        from.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let lines = NSStackView(views: [titleLabel] + (items.count > 1 ? [preview] : []) + [from])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 3
        for line in lines.arrangedSubviews {
            line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let heading = NSStackView(views: [icon, lines])
        heading.alignment = .centerY
        heading.spacing = 12
        return heading
    }

    private func buildAdvanced(selectedTargetFolders: Int) {
        let store = AppDefaults.store
        pinButton.setButtonType(.toggle)
        pinButton.bezelStyle = .toolbar
        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: String(localized: "Keep options open"))
        pinButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
        pinButton.state = store.bool(forKey: Key.pinned) ? .on : .off
        pinButton.toolTip = String(localized: "Always show these options")
        pinButton.target = self
        pinButton.action = #selector(togglePin(_:))

        for mode in OverwriteMode.allCases {
            overwritePopUp.addItem(withTitle: Settings.isModern ? mode.plainTitle : mode.title)
        }
        overwritePopUp.selectItem(at: Settings.copyOverwriteMode.rawValue - 1)
        overwritePopUp.target = self
        overwritePopUp.action = #selector(optionsChanged(_:))
        saveButton.bezelStyle = .toolbar
        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down",
                                   accessibilityDescription: String(localized: "Save as default"))
        saveButton.toolTip = String(localized: "Save these options as the default")
        saveButton.target = self
        saveButton.action = #selector(saveDefaults(_:))

        skipUnreadableBox.state = Settings.copySkipsUnreadable ? .on : .off
        overwriteLockedBox.state = Settings.copyOverwritesLocked ? .on : .off
        skipDSStoreBox.state = Settings.copySkipsDSStore ? .on : .off
        skipDSStoreBox.identifier = NSUserInterfaceItemIdentifier("copySkipDSStore")
        for button in [skipUnreadableBox, overwriteLockedBox, skipDSStoreBox, allFoldersBox] {
            button.target = self
            button.action = #selector(optionsChanged(_:))
        }
        allFoldersBox.isEnabled = selectedTargetFolders > 0
        if selectedTargetFolders > 0 {
            allFoldersBox.title = String(localized: "Copy to all \(selectedTargetFolders) selected folders in the target panel")
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let content = NSStackView(views: [
            row(NSTextField(labelWithString: String(localized: "Overwrite options")), spacer, pinButton),
            row(overwritePopUp, saveButton),
            skipUnreadableBox,
            overwriteLockedBox,
            skipDSStoreBox,
            allFoldersBox,
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        for view in content.arrangedSubviews.prefix(2) {
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -24).isActive = true
        }
        // A rounded group, as System Settings sets options apart.
        advanced.title = String(localized: "Advanced options")
        advanced.titlePosition = .noTitle
        advanced.boxType = .custom
        advanced.borderWidth = 0
        advanced.cornerRadius = 10
        advanced.fillColor = .quinarySystemFill
        advanced.setAccessibilityLabel(advanced.title)
        // Pinned to the box's content view, so the box gets the height it needs.
        content.translatesAutoresizingMaskIntoConstraints = false
        advanced.contentView?.addSubview(content)
        if let box = advanced.contentView {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: box.topAnchor),
                content.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                content.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            ])
        }
    }

    private func row(_ views: NSView...) -> NSStackView {
        let row = NSStackView(views: views)
        row.spacing = 6
        row.distribution = .fill
        views.first?.setContentHuggingPriority(.init(200), for: .horizontal)
        return row
    }

    @objc private func optionsChanged(_ sender: Any?) { updateOptionsSummary(); resize() }

    private func updateOptionsSummary() {
        let mode = overwritePopUp.titleOfSelectedItem ?? OverwriteMode.ask.plainTitle
        var parts = [String(localized: "Existing files: \(mode)")]
        let filter = filterBox.stringValue.trimmingCharacters(in: .whitespaces)
        if !filter.isEmpty { parts.append(String(localized: "Only: \(filter)")) }
        if skipUnreadableBox.state == .on { parts.append(String(localized: "Skip unreadable files")) }
        if overwriteLockedBox.state == .on { parts.append(String(localized: "Replace locked files")) }
        if skipDSStoreBox.state == .off { parts.append(String(localized: "Copy .DS_Store")) }
        if allFoldersBox.isEnabled && allFoldersBox.state == .on { parts.append(allFoldersBox.title) }
        optionsSummary.stringValue = parts.joined(separator: " · ")
    }

    private static func functionKey(_ number: Int) -> String {
        String(UnicodeScalar(UInt32(NSF1FunctionKey + number - 1))!)
    }

    // MARK: - Lists

    private static func list(_ key: String) -> [String] {
        AppDefaults.store.stringArray(forKey: key) ?? []
    }

    private static func setList(_ list: [String], _ key: String) {
        AppDefaults.store.set(list, forKey: key)
    }

    /// The folder part of the target text ("/Users/me/*.*" → "/Users/me/").
    private var targetFolder: String {
        let text = targetBox.stringValue
        guard let slash = text.lastIndex(of: "/") else { return text }
        return String(text[...slash])
    }

    private func reloadTargetItems() {
        let saved = Self.list(Key.targetList)
        let history = Self.list(Key.targetHistory).filter { !saved.contains($0) }
        targetBox.removeAllItems()
        targetBox.addItems(withObjectValues: (saved + history).map { $0 + Self.mask })
        updateTargetListButton()
    }

    private func updateTargetListButton() {
        let listed = Self.list(Key.targetList).contains(targetFolder)
        if Settings.isModern {
            targetListButton.title = listed ? String(localized: "Remove from the Target List") : String(localized: "Add to the Target List")
            targetListButton.image = NSImage(systemSymbolName: listed ? "star.fill" : "star", accessibilityDescription: nil)
            targetListButton.imagePosition = .imageOnly
            targetListButton.contentTintColor = listed ? .controlAccentColor : nil
        } else {
            targetListButton.title = listed ? "− F7" : "+ F7"
        }
    }

    private func reloadFilterItems() {
        let saved = Self.list(Key.filterList)
        let history = Self.list(Key.filterHistory).filter { !saved.contains($0) }
        filterBox.removeAllItems()
        filterBox.addItems(withObjectValues: saved + history)
    }

    /// "+F7": adds the target folder to the target list, or removes it.
    @objc private func toggleTargetList(_ sender: Any?) {
        let folder = targetFolder
        guard folder.hasPrefix("/") || folder.hasPrefix("~") else {
            NSSound.beep()
            return
        }
        var saved = Self.list(Key.targetList)
        if let index = saved.firstIndex(of: folder) {
            saved.remove(at: index)
        } else {
            saved.append(folder)
        }
        Self.setList(saved, Key.targetList)
        reloadTargetItems()
    }

    /// "+F8": saved filters, adding or removing the current one, and examples.
    @objc private func showFilterMenu(_ sender: Any?) {
        let menu = NSMenu()
        let current = filterBox.stringValue.trimmingCharacters(in: .whitespaces)
        let saved = Self.list(Key.filterList)
        if !current.isEmpty {
            let isSaved = saved.contains(current)
            let toggle = NSMenuItem(title: isSaved ? String(localized: "Remove \u{201C}\(current)\u{201D} from the list")
                                        : String(localized: "Add \u{201C}\(current)\u{201D} to the list"),
                                    action: #selector(toggleFilterList(_:)), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
        }
        if !saved.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for filter in saved {
                menu.addItem(filterItem(filter, title: filter))
            }
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let examples = NSMenuItem(title: String(localized: "Examples"), action: nil, keyEquivalent: "")
        examples.isEnabled = false
        menu.addItem(examples)
        for (filter, title) in [
            ("*.jpg *.jpeg *.png *.gif *.heic", String(localized: "Pictures")),
            ("*.txt *.md *.rtf *.pdf *.doc *.docx", String(localized: "Documents")),
            ("*.* | .git/ node_modules/ .DS_Store", String(localized: "Everything except .git, node_modules, .DS_Store")),
            ("src/", String(localized: "Only folders named src, at any depth")),
        ] {
            menu.addItem(filterItem(filter, title: "\(filter)  —  \(title)"))
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: String(localized: "Copy all files"), action: #selector(clearFilter(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: filterButton.bounds.height + 4), in: filterButton)
    }

    private func filterItem(_ filter: String, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(chooseFilter(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = filter
        return item
    }

    @objc private func toggleFilterList(_ sender: Any?) {
        let current = filterBox.stringValue.trimmingCharacters(in: .whitespaces)
        var saved = Self.list(Key.filterList)
        if let index = saved.firstIndex(of: current) {
            saved.remove(at: index)
        } else {
            saved.append(current)
        }
        Self.setList(saved, Key.filterList)
        reloadFilterItems()
    }

    @objc private func chooseFilter(_ sender: NSMenuItem) {
        filterBox.stringValue = sender.representedObject as? String ?? ""
        updateOptionsSummary()
        resize()
    }

    @objc private func clearFilter(_ sender: Any?) {
        filterBox.stringValue = ""
        updateOptionsSummary()
        resize()
    }

    /// ⌃D: a folder from the directory hotlist becomes the target.
    private func showHotlist() {
        let menu = NSMenu()
        for path in Hotlist.directories {
            let item = NSMenuItem(title: (path as NSString).abbreviatingWithTildeInPath,
                                  action: #selector(chooseHotlistFolder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: String(localized: "The directory hotlist is empty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: targetBox.bounds.height + 4), in: targetBox)
    }

    @objc private func chooseHotlistFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        setTargetFolder(path)
    }

    private func setTargetFolder(_ path: String) {
        let text = targetBox.stringValue
        let mask = text.lastIndex(of: "/").map { String(text[text.index(after: $0)...]) } ?? Self.mask
        targetBox.stringValue = (path.hasSuffix("/") ? path : path + "/") + (mask.isEmpty ? Self.mask : mask)
        updateTargetListButton()
    }

    // MARK: - Actions

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .control, event.shortcutCharacters == "d" {
            showHotlist()
            return true
        }
        return false
    }

    /// "Tree": picks the target folder.
    @objc private func chooseFolder(_ sender: Any?) {
        let open = NSOpenPanel()
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.canCreateDirectories = true
        open.prompt = String(localized: "Choose")
        let folder = (targetFolder as NSString).expandingTildeInPath
        if folder.hasPrefix("/") {
            open.directoryURL = URL(filePath: folder, directoryHint: .isDirectory)
        }
        open.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = open.url else { return }
            self?.setTargetFolder(url.path)
        }
    }

    /// Options >> shows the options; the modern look's Options shows or hides them.
    @objc private func expand(_ sender: Any?) {
        let shows = !Settings.isModern || advanced.isHidden
        advanced.isHidden = !shows
        if Settings.isModern {
            updateOptionsButton()
        } else {
            optionsButton.isHidden = true
        }
        resize()
        if shows { panel.makeFirstResponder(overwritePopUp) }
    }

    /// The modern look's Options: a chevron down while the options are hidden, up while shown.
    private func updateOptionsButton() {
        optionsButton.image = NSImage(systemSymbolName: advanced.isHidden ? "chevron.down" : "chevron.up",
                                      accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
    }

    @objc private func togglePin(_ sender: NSButton) {
        AppDefaults.store.set(sender.state == .on, forKey: Key.pinned)
    }

    @objc private func saveDefaults(_ sender: Any?) {
        Settings.copyOverwriteMode = OverwriteMode(rawValue: overwritePopUp.indexOfSelectedItem + 1) ?? .ask
        Settings.copySkipsUnreadable = skipUnreadableBox.state == .on
        Settings.copyOverwritesLocked = overwriteLockedBox.state == .on
        Settings.copySkipsDSStore = skipDSStoreBox.state == .on
        Settings.copyVerifies = verifyBox.state == .on
        Settings.copyAttributes = attributesBox.state == .on
        saveButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [saveButton] in
            saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        }
    }

    private func resize() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = panel.frame
        let height = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size)).height
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: true)
    }

    private func switchMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: kind == .copy ? String(localized: "move.button", defaultValue: "Move")
                                  : String(localized: "copy.button", defaultValue: "Copy"),
                              action: #selector(confirmSwitched(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func confirm(_ sender: NSButton) {
        finish(kind: kind, queued: sender === queueButton)
    }

    /// The right-click menu of OK / F2 Queue: the other operation.
    @objc private func confirmSwitched(_ sender: NSMenuItem) {
        let queued = sender.menu === queueButton.menu
        finish(kind: kind == .copy ? .move : .copy, queued: queued)
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    private func finish(kind: TransferJob.Kind, queued: Bool) {
        let target = targetBox.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            NSSound.beep()
            return
        }
        let filter = filterBox.stringValue.trimmingCharacters(in: .whitespaces)
        remember(targetFolder, in: Key.targetHistory)
        if !filter.isEmpty {
            remember(filter, in: Key.filterHistory)
        }
        var options = TransferOptions()
        options.filter = CopyFilter(filter)
        options.verify = verifyBox.state == .on
        options.copiesAttributes = attributesBox.state == .on
        options.overwrite = OverwriteMode(rawValue: overwritePopUp.indexOfSelectedItem + 1) ?? .ask
        options.skipsUnreadable = skipUnreadableBox.state == .on
        options.overwritesLocked = overwriteLockedBox.state == .on
        options.skipsDSStore = skipDSStoreBox.state == .on
        let result = Result(kind: kind, target: target, options: options, queued: queued,
                            toAllSelectedFolders: allFoldersBox.isEnabled && allFoldersBox.state == .on)
        close()
        completion(result)
    }

    private func remember(_ value: String, in key: String) {
        var list = Self.list(key).filter { $0 != value }
        list.insert(value, at: 0)
        Self.setList(Array(list.prefix(Self.historyLimit)), key)
    }

    private func close() {
        parent?.endSheet(panel)
        panel.orderOut(nil)
        Self.current = nil
    }
}

extension CopyDialog: NSComboBoxDelegate {
    func controlTextDidChange(_ notification: Notification) {
        updateTargetListButton()
        updateOptionsSummary()
        resize()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateTargetListButton()
            self?.updateOptionsSummary()
            self?.resize()
        }
    }
}

/// Lets the dialog see ⌃D before the text field does.
private final class CopyDialogPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}
