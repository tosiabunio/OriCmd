import AppKit
import os

/// Tab navigation, transfer between panels and folder history.
extension FilePanelController {
    // MARK: - Tabs

    /// The tabs as saved between launches: their folders (a locked tab's own one),
    /// locks and names, and the active tab.
    var tabState: SavedTabs {
        tabs[activeTabIndex] = currentTab()
        return SavedTabs(directories: tabs.map { ($0.lockedDirectory ?? $0.directory).path },
                         locks: tabs.map(\.lock.rawValue), names: tabs.map { $0.name ?? "" }, active: activeTabIndex)
    }

    /// Tabs of a panel kept in the defaults (between launches, or as favorites).
    struct SavedTabs {
        var directories: [String]
        var locks: [Int]
        var names: [String]
        var active: Int

        var dictionary: [String: Any] {
            ["tabs": directories, "locks": locks, "names": names, "active": active]
        }

        init(directories: [String], locks: [Int], names: [String], active: Int) {
            (self.directories, self.locks, self.names, self.active) = (directories, locks, names, active)
        }

        init(_ dictionary: [String: Any]?) {
            directories = dictionary?["tabs"] as? [String] ?? []
            locks = dictionary?["locks"] as? [Int] ?? []
            names = dictionary?["names"] as? [String] ?? []
            active = dictionary?["active"] as? Int ?? 0
        }

        /// The tabs whose folders still exist (the active one kept active if it does).
        func tabs(sortOrder: SortOrder) -> (tabs: [Tab], active: Int) {
            var tabs: [Tab] = []
            var activeIndex = 0
            for (index, path) in directories.enumerated() where FileManager.default.fileExists(atPath: path) {
                if index == active { activeIndex = tabs.count }
                var tab = Tab(directory: URL(filePath: path), sortOrder: sortOrder)
                tab.lock = locks.indices.contains(index) ? Tab.Lock(rawValue: locks[index]) ?? .none : .none
                tab.lockedDirectory = tab.lock == .none ? nil : tab.directory
                tab.name = names.indices.contains(index) && !names[index].isEmpty ? names[index] : nil
                tabs.append(tab)
            }
            return (tabs, activeIndex)
        }
    }

    /// Shows `saved` tabs instead of the panel's (asking first when a program still
    /// runs in a server terminal of a tab closed); none existing: nothing changes.
    func replaceTabs(with saved: SavedTabs) {
        let (newTabs, active) = saved.tabs(sortOrder: sortOrder)
        guard !newTabs.isEmpty else {
            NSSound.beep()
            return
        }
        confirmClosing(terminals(ofTabs: Array(tabs.indices))) { [weak self] in
            guard let self else { return }
            if panelView.terminalPane.hasFocus { focus() }
            terminals(ofTabs: Array(tabs.indices)).forEach(panelView.terminalPane.close)
            tabs = newTabs
            activateTab(at: active)
        }
    }

    /// A locked tab keeps its folder: before going to `target` (or anywhere else
    /// when nil, as into an archive or a server) a new tab opens beside it, and
    /// it goes there instead. A tab locked with folder changes allowed goes, except
    /// to a server.
    func leaveLockedTab(for target: URL?) {
        let tab = tabs[activeTabIndex]
        guard tab.lock == .locked || (tab.lock == .allowsChanges && target == nil) else { return }
        if let target, target.standardizedFileURL == tab.lockedDirectory { return }
        tabs[activeTabIndex] = currentTab()
        var opened = Tab(directory: directory, sortOrder: sortOrder)
        opened.backHistory = backHistory
        opened.forwardHistory = forwardHistory
        tabs.insert(opened, at: activeTabIndex + 1)
        activeTabIndex += 1
        updateTabBar()
    }

    /// Locks the tab to its folder, or unlocks it.
    @objc(cm_ToggleLockCurrentTab:)
    func toggleLockCurrentTab(_ sender: Any?) {
        toggleLock(.locked, of: activeTabIndex)
    }

    /// cm_ToggleLockDcaCurrentTab: locked, but the folder may change; the tab comes
    /// back to its folder when chosen again.
    @objc(cm_ToggleLockDcaCurrentTab:)
    func toggleLockDcaCurrentTab(_ sender: Any?) {
        toggleLock(.allowsChanges, of: activeTabIndex)
    }

    /// Only a local folder (not a server, an archive or found files) is locked.
    private func toggleLock(_ lock: Tab.Lock, of index: Int) {
        guard tabs.indices.contains(index) else { return }
        if index == activeTabIndex { tabs[index] = currentTab() }
        if tabs[index].lock == lock {
            tabs[index].lock = .none
            tabs[index].lockedDirectory = nil
        } else {
            guard canLock(index) else {
                NSSound.beep()
                return
            }
            tabs[index].lock = lock
            tabs[index].lockedDirectory = tabs[index].lockedDirectory ?? tabs[index].directory.standardizedFileURL
        }
        updateTabBar()
    }

    private func canLock(_ index: Int) -> Bool {
        index == activeTabIndex ? remote == nil && archive == nil && searchResults == nil : tabs[index].remote == nil
    }

    /// Asks for the tab's own name; an empty one shows the folder's again.
    private func renameTab(_ index: Int) {
        guard tabs.indices.contains(index), let window = view.window else { return }
        let id = tabs[index].id
        let shown = index == activeTabIndex ? currentTab() : tabs[index]
        var unnamed = shown
        unnamed.name = nil
        unnamed.lock = .none
        Prompt.text(String(localized: "Rename Tab"), message: String(localized: "The tab's name (empty: the folder's):"),
                    initial: shown.name ?? unnamed.title, okTitle: String(localized: "Rename"), in: window) { [weak self] text in
            guard let self, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
            let name = text.trimmingCharacters(in: .whitespaces)
            tabs[index].name = name.isEmpty ? nil : name
            updateTabBar()
        }
    }

    /// Opens a tab for the local `directory` (a server is never in two tabs: from a
    /// server tab ⌘T opens the folder the tab goes back to).
    func openTab(_ directory: URL) {
        tabs[activeTabIndex] = currentTab()
        tabs.insert(Tab(directory: directory, sortOrder: sortOrder), at: activeTabIndex + 1)
        activateTab(at: activeTabIndex + 1)
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index), index != activeTabIndex else { return }
        tabs[activeTabIndex] = currentTab()
        activateTab(at: index)
    }

    /// The last tab is never closed, as in Total Commander. A server tab's terminal
    /// ends with it (after asking when a program still runs there).
    func closeTab(_ index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else {
            NSSound.beep()
            return
        }
        let id = tabs[index].id
        confirmClosing(terminals(ofTabs: [index])) { [weak self] in
            guard let self, tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
            if index == activeTabIndex, panelView.terminalPane.hasFocus { focus() }
            terminals(ofTabs: [index]).forEach(panelView.terminalPane.close)
            removeTab(index)
        }
    }

    private func removeTab(_ index: Int) {
        tabs.remove(at: index)
        if index == activeTabIndex {
            activateTab(at: min(index, tabs.count - 1))
        } else {
            if index < activeTabIndex { activeTabIndex -= 1 }
            updateTabBar()
            delegate?.filePanelDidChangeDirectory(self)
        }
    }

    func tabMenu(for index: Int) -> NSMenu {
        let menu = NSMenu()
        let lock = tabs[index].lock
        for (title, action) in [(String(localized: "Close Tab"), #selector(closeTabFromMenu(_:))),
                                (String(localized: "Close Other Tabs"), #selector(closeOtherTabs(_:))),
                                (String(localized: "Duplicate Tab"), #selector(duplicateTab(_:))),
                                ("-", nil),
                                (Command.toggleLockCurrentTab.title, #selector(lockTabFromMenu(_:))),
                                (Command.toggleLockDcaCurrentTab.title, #selector(lockTabAllowingChangesFromMenu(_:))),
                                (String(localized: "Rename Tab…"), #selector(renameTabFromMenu(_:)))] as [(String, Selector?)] {
            guard let action else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            switch action {
            case #selector(duplicateTab(_:)):
                item.isEnabled = !isServerTab(index)
            case #selector(lockTabFromMenu(_:)), #selector(lockTabAllowingChangesFromMenu(_:)):
                let mine: Tab.Lock = action == #selector(lockTabFromMenu(_:)) ? .locked : .allowsChanges
                item.state = lock == mine ? .on : .off
                item.isEnabled = lock == mine || canLock(index)
            case #selector(renameTabFromMenu(_:)):
                item.isEnabled = true
            default:
                item.isEnabled = tabs.count > 1
            }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        return menu
    }

    @objc private func lockTabFromMenu(_ sender: NSMenuItem) {
        toggleLock(.locked, of: sender.tag)
    }

    @objc private func lockTabAllowingChangesFromMenu(_ sender: NSMenuItem) {
        toggleLock(.allowsChanges, of: sender.tag)
    }

    @objc private func renameTabFromMenu(_ sender: NSMenuItem) {
        renameTab(sender.tag)
    }

    @objc private func closeTabFromMenu(_ sender: NSMenuItem) {
        closeTab(sender.tag)
    }

    @objc private func closeOtherTabs(_ sender: NSMenuItem) {
        selectTab(sender.tag)
        let keepID = tabs[activeTabIndex].id
        let otherIDs = Set(tabs.map(\.id)).subtracting([keepID])
        confirmClosing(terminals(ofTabs: tabs.indices.filter { $0 != activeTabIndex })) { [weak self] in
            // The tabs asked about are closed; any opened meanwhile stay.
            guard let self, let keep = tabs.firstIndex(where: { $0.id == keepID }) else { return }
            selectTab(keep)
            terminals(ofTabs: tabs.indices.filter { otherIDs.contains(tabs[$0].id) })
                .forEach(panelView.terminalPane.close)
            tabs.removeAll { otherIDs.contains($0.id) }
            activeTabIndex = tabs.firstIndex { $0.id == keepID } ?? 0
            updateTabBar()
            delegate?.filePanelDidChangeDirectory(self)
        }
    }

    /// Only local tabs are duplicated: a server stays in its own tab.
    @objc private func duplicateTab(_ sender: NSMenuItem) {
        guard !isServerTab(sender.tag) else { return }
        selectTab(sender.tag)
        openTab(directory)
    }

    private func isServerTab(_ index: Int) -> Bool {
        index == activeTabIndex ? remote != nil : tabs.indices.contains(index) && tabs[index].remote != nil
    }

    func terminals(ofTabs indices: [Int]) -> [ShellTerminalView] {
        indices.compactMap { $0 == activeTabIndex ? panelView.terminalPane.terminal : tabs[$0].terminal }
    }

    /// The active tab as it is now.
    private func currentTab() -> Tab {
        var tab = tabs[activeTabIndex]
        tab.directory = directory
        tab.selectedName = listView.currentItem?.name
        tab.sortOrder = sortOrder
        tab.backHistory = backHistory
        tab.forwardHistory = forwardHistory
        tab.remote = remote
        tab.terminal = panelView.terminalPane.terminal
        tab.showsTerminal = panelView.isTerminalVisible
        return tab
    }

    /// Shows the tab: its local folder, or its server with the terminal as it was left.
    /// The terminal of the tab left keeps running there, hidden.
    private func activateTab(at index: Int) {
        activeTabIndex = index
        let tab = tabs[index]
        backHistory = tab.backHistory
        forwardHistory = tab.forwardHistory
        if sortOrder != tab.sortOrder {
            sortOrder = tab.sortOrder
        }
        terminalStart = nil
        if panelView.terminalPane.hasFocus { focus() }
        panelView.terminalPane.attach(tab.terminal)
        panelView.setTerminalVisible(tab.terminal != nil && tab.showsTerminal)
        if let server = tab.remote {
            // Nothing of the folder shown before stays (an archive, found files, a filter).
            archive = nil
            searchResults = nil
            isBranchView = false
            quickFilter = nil
            onlyNames = nil
            watcher = nil
            listView.folderSizes = [:]
            remote = server
            directory = tab.directory
            entries = []
            listView.setMarked([])
            panelView.pathBar.showsMask = false
            updatePathBar()
            refreshList(selecting: nil)
            loadRemote(server.path, selecting: tab.selectedName)
            if tab.terminal == nil, tab.showsTerminal {
                openTerminal(focusing: false)
            }
        } else {
            clearRemote()
            // A tab locked with folder changes allowed comes back to its folder.
            if tab.lock == .allowsChanges, let locked = tab.lockedDirectory, locked != tab.directory.standardizedFileURL {
                load(locked, recordingHistory: false)
            } else {
                load(tab.directory, selecting: tab.selectedName, recordingHistory: false)
            }
        }
        updateTabBar()
        delegate?.filePanelDidChangeDirectory(self)
    }

    /// The active tab's title follows the panel (a server folder, too).
    func updateTabBar() {
        let shown = tabs.indices.map { $0 == activeTabIndex ? currentTab() : tabs[$0] }
        panelView.setTabs(shown.map(\.title), icons: shown.map(\.icon), identifiers: tabs.map(\.id), selected: activeTabIndex,
                          visible: tabs.count > 1 || alwaysShowsTabBar)
    }

    // MARK: - Dragging tabs

    /// A tab dropped on the tab bar before `index`: one of this panel's moves there,
    /// the other panel's comes over (its server and terminal too) and is shown.
    func dropTab(_ id: UUID, at index: Int) -> Bool {
        if let from = tabs.firstIndex(where: { $0.id == id }) {
            moveTab(from: from, to: index)
            return true
        }
        guard let tab = delegate?.filePanel(self, takeTab: id) else {
            NSSound.beep()
            return false
        }
        tabs[activeTabIndex] = currentTab()
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        activateTab(at: min(max(index, 0), tabs.count - 1))
        focus()
        return true
    }

    private func moveTab(from: Int, to index: Int) {
        let destination = index > from ? index - 1 : index
        guard destination != from else { return }
        tabs[activeTabIndex] = currentTab()
        let activeID = tabs[activeTabIndex].id
        tabs.insert(tabs.remove(at: from), at: min(max(destination, 0), tabs.count - 1))
        activeTabIndex = tabs.firstIndex { $0.id == activeID } ?? 0
        updateTabBar()
        delegate?.filePanelDidChangeDirectory(self)
    }

    /// The tab `id` as it is now, for the other panel: taken out of this one, or,
    /// when it is the only tab, copied (a server stays: it is never in two tabs).
    func giveTab(_ id: UUID) -> Tab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let tab = index == activeTabIndex ? currentTab() : tabs[index]
        guard tabs.count > 1 else {
            guard tab.remote == nil else { return nil }
            var copy = Tab(directory: tab.directory, sortOrder: tab.sortOrder)
            copy.selectedName = tab.selectedName
            copy.backHistory = tab.backHistory
            copy.forwardHistory = tab.forwardHistory
            return copy
        }
        // A terminal still starting would be left behind: the tab waits for it.
        guard index != activeTabIndex || terminalStart == nil else { return nil }
        if index == activeTabIndex, panelView.terminalPane.hasFocus { focus() }
        tabs[index] = tab
        removeTab(index)
        return tab
    }

    func goBack() {
        guard !backHistory.isEmpty else {
            NSSound.beep()
            return
        }
        // Leaving a server may be cancelled: the history changes only after that.
        if remote != nil {
            leaveServer { [weak self] in self?.goBack() }
            return
        }
        let entry = backHistory.removeLast()
        forwardHistory.append(HistoryEntry(directory: directory, selectedName: listView.currentItem?.name))
        load(entry.directory, selecting: entry.selectedName, recordingHistory: false)
    }

    func goForward() {
        guard !forwardHistory.isEmpty else {
            NSSound.beep()
            return
        }
        if remote != nil {
            leaveServer { [weak self] in self?.goForward() }
            return
        }
        let entry = forwardHistory.removeLast()
        backHistory.append(HistoryEntry(directory: directory, selectedName: listView.currentItem?.name))
        load(entry.directory, selecting: entry.selectedName, recordingHistory: false)
    }

    /// Recently visited folders, most recent first, without duplicates.
    var recentDirectories: [URL] {
        var seen: Set<URL> = [directory]
        return backHistory.reversed().map(\.directory).filter { seen.insert($0).inserted }
    }

}
