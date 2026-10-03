import AppKit
import os

/// Tab navigation, transfer between panels and folder history.
extension FilePanelController {
    // MARK: - Tabs

    /// Tab directories and the active tab, for saving the panel between launches.
    var tabState: (directories: [String], active: Int) {
        (tabs.map(\.directory.path), activeTabIndex)
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
        for (title, action) in [(String(localized: "Close Tab"), #selector(closeTabFromMenu(_:))),
                                (String(localized: "Close Other Tabs"), #selector(closeOtherTabs(_:))),
                                (String(localized: "Duplicate Tab"), #selector(duplicateTab(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = action == #selector(duplicateTab(_:)) ? !isServerTab(index) : tabs.count > 1
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        return menu
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
            load(tab.directory, selecting: tab.selectedName, recordingHistory: false)
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
