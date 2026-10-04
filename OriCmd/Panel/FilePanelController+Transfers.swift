import AppKit
import os

/// Transfer orchestration and clipboard delivery for a panel.
extension FilePanelController {
    /// Downloads one file of the server into a new temporary folder.
    func downloadToTemporaryFolder(_ item: FileItem) async -> URL? {
        guard let remote, let window = view.window else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "OriCmd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = remote.path(of: item.name)
        let controller = TransferController(title: String(localized: "Downloading"),
                                            failureTitle: String(localized: "Download failed"), window: window)
        let done = await controller.run(source: path, target: folder.path) { progress, _ in
            // A new, empty folder: nothing to ask about.
            _ = try await remote.fileSystem.download([item], from: remote.path, to: folder, progress: progress,
                                                     conflicts: RemoteConflicts(nil))
            return [folder]
        }
        return done.isEmpty ? nil : folder.appending(path: item.name)
    }

    /// Uploads local files into the server folder shown here (or `folder`);
    /// moving deletes the originals afterwards.
    func upload(_ urls: [URL], to folder: String? = nil, moving: Bool, then finished: (() -> Void)? = nil) {
        guard let remote, let window = view.window else { return }
        let target = folder ?? remote.path
        Task {
            let controller = TransferController(title: String(localized: "Uploading"),
                                                failureTitle: String(localized: "Upload failed"), window: window)
            let done = await controller.run(source: urls.first?.deletingLastPathComponent().path ?? "",
                                            target: remote.fileSystem.displayName + target) { progress, prompts in
                let completed = try await remote.fileSystem.upload(urls, to: target, progress: progress,
                                                                   conflicts: RemoteConflicts(prompts.resolveConflict))
                // Moving deletes only what reached the server completely.
                if moving {
                    try await FileOperations.deletePermanently(urls.filter(completed.contains))
                }
                return urls.filter(completed.contains)
            }
            if !done.isEmpty {
                loadRemote(remote.path, selecting: urls.first?.lastPathComponent)
            }
            finished?()
        }
    }

    /// Downloads entries of the server folder shown here into a local folder;
    /// moving deletes them on the server afterwards. Returns whether it worked.
    func download(_ items: [FileItem], to folder: URL, moving: Bool) async -> Bool {
        guard let remote, let window = view.window else { return false }
        let controller = TransferController(title: String(localized: "Downloading"),
                                            failureTitle: String(localized: "Download failed"), window: window)
        let completed = OSAllocatedUnfairLock(initialState: Set<String>())
        let done = await controller.run(source: remote.displayPath, target: folder.path) { progress, prompts in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let names = try await remote.fileSystem.download(items, from: remote.path, to: folder, progress: progress,
                                                             conflicts: RemoteConflicts(prompts.resolveConflict))
            completed.withLock { $0 = names }
            // Moving deletes on the server only what arrived completely (skipped files stay).
            if moving {
                try await remote.fileSystem.delete(items.filter { names.contains($0.name) }, in: remote.path)
            }
            return [folder]
        }
        if !done.isEmpty {
            listView.setMarked(listView.marked.subtracting(completed.withLock { $0 }))
            if moving {
                loadRemote(remote.path, selecting: nil)
            }
        }
        return !done.isEmpty
    }

    // MARK: - Clipboard

    /// Files cut with ⌘X: pasting them (while the clipboard is unchanged) moves them.
    private static var cutClipboard: (changeCount: Int, urls: [URL])?

    @objc func copy(_ sender: Any?) {
        writeSelectionToClipboard(cut: false)
    }

    @objc func cut(_ sender: Any?) {
        writeSelectionToClipboard(cut: true)
    }

    @objc func paste(_ sender: Any?) {
        pasteFiles(moving: false)
    }

    /// ⌥⌘V, like Finder's "Move Item Here".
    @objc func moveItemsHere(_ sender: Any?) {
        pasteFiles(moving: true)
    }

    private func writeSelectionToClipboard(cut: Bool) {
        let urls = selectedItems.map(\.url)
        guard archive == nil, remote == nil, !urls.isEmpty else {
            NSSound.beep()
            return
        }
        let pasteboard = AppDefaults.pasteboard
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        Self.cutClipboard = cut ? (pasteboard.changeCount, urls) : nil
    }

    var clipboardFiles: [URL] {
        (AppDefaults.pasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func pasteFiles(moving forceMove: Bool) {
        let pasteboard = AppDefaults.pasteboard
        // Files another program promised (Remote Desktop, virtual machines) come from the
        // program itself: the file URLs next to the promise point to placeholders.
        if PromisedFiles.areOffered(on: pasteboard) {
            pastePromisedFiles(from: pasteboard.name)
            return
        }
        let urls = clipboardFiles
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        let moving = forceMove || Self.cutClipboard?.changeCount == pasteboard.changeCount
        if moving { Self.cutClipboard = nil }
        whenWritten(urls) { [weak self] in self?.paste(urls, moving: moving) }
    }

    /// Runs `proceed` once the programs that put `urls` on the clipboard (or drag them)
    /// have written them (see FileCoordination). A wait longer than half a second
    /// shows "Receiving Files…" with Cancel.
    func whenWritten(_ urls: [URL], then proceed: @escaping () -> Void) {
        guard let window = view.window else { return }
        let waiting = Task { try await FileCoordination.waitUntilWritten(urls) }
        let progress = ProgressSheet()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !progress.isFinished else { return }
            progress.close = Prompt.progress(String(localized: "Receiving Files…"), in: window) { waiting.cancel() }
        }
        Task {
            let result = await waiting.result
            progress.finish()
            switch result {
            case .success:
                proceed()
            case .failure(let error) where !(error is CancellationError):
                Prompt.error(String(localized: "Cannot paste the files"), error, in: window)
            case .failure:
                break
            }
        }
    }

    func paste(_ urls: [URL], moving: Bool) {
        if remote != nil {
            upload(urls, moving: moving)
            return
        }
        if let archive {
            guard !refuseReadOnlyArchive() else { return }
            applyArchiveEdit(.add(urls, folder: archive.folder), selecting: urls.first?.lastPathComponent) { succeeded in
                guard succeeded, moving else { return }
                Task { try? await FileOperations.deletePermanently(urls) }
            }
            return
        }
        transfer(urls, to: directory, moving: moving)
    }

    /// Asks the program that copied them for the promised files, into a private folder
    /// on this folder's volume, then moves them in (or uploads them, or adds them to
    /// the archive). The program may take a while: Cancel stops waiting for it.
    private func pastePromisedFiles(from pasteboard: NSPasteboard.Name) {
        guard let window = view.window, !refuseReadOnlyArchive() else { return }
        let base = remote == nil && archive == nil ? directory : FileManager.default.temporaryDirectory
        guard let folder = try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                         appropriateFor: base, create: true) else {
            NSSound.beep()
            return
        }
        let cleanUp: () -> Void = { try? FileManager.default.removeItem(at: folder) }
        var cancelled = false
        let closeProgress = Prompt.progress(String(localized: "Receiving Files…"),
                                            in: window) { cancelled = true }
        Task {
            let result = await Task.detached { try PromisedFiles.receive(from: pasteboard, into: folder) }.result
            closeProgress()
            guard !cancelled else {
                cleanUp()
                return
            }
            switch result {
            case .failure(let error):
                cleanUp()
                Prompt.error(String(localized: "Cannot paste the files"), error, in: window)
            case .success(let files) where files.isEmpty:
                cleanUp()
                NSSound.beep()
            case .success(let files):
                deliver(files, then: cleanUp)
            }
        }
    }

    /// Moves received files from a private folder to where the panel is.
    private func deliver(_ files: [URL], then finished: @escaping () -> Void) {
        if remote != nil {
            upload(files, moving: true, then: finished)
        } else if let archive {
            applyArchiveEdit(.add(files, folder: archive.folder), selecting: files.first?.lastPathComponent) { _ in
                finished()
            }
        } else {
            transfer(files, to: directory, moving: true, then: finished)
        }
    }

    /// Copies or moves files into `destination` (paste, drag and drop). Items
    /// already in that folder are duplicated as "name copy" instead.
    func transfer(_ urls: [URL], to destination: URL, moving: Bool, then finished: (() -> Void)? = nil) {
        guard let window = view.window else { return }
        Task {
            let controller = moving
                ? TransferController(title: String(localized: "Moving"), failureTitle: String(localized: "Moving failed"),
                                     window: window)
                : TransferController(title: String(localized: "Copying"), failureTitle: String(localized: "Copying failed"),
                                     window: window)
            var options = TransferOptions()
            options.skipsDSStore = Settings.copySkipsDSStore
            _ = await controller.run(source: urls[0].deletingLastPathComponent().path, target: destination.path) {
                [options] progress, prompts in
                let total = urls.reduce(Int64(0)) { $0 + TransferEngine.totalSize(of: $1) }
                progress.update { $0.totalBytes = total }
                // Items from another folder go in one job, so "Overwrite All" / "Skip All"
                // hold for all of them; items of this folder become "name copy".
                var others: [URL] = []
                for url in urls {
                    guard url.deletingLastPathComponent().standardizedFileURL.path == destination.standardizedFileURL.path else {
                        others.append(url)
                        continue
                    }
                    if moving { continue }
                    let job = TransferJob(kind: .copy, sources: [url], destination: destination,
                                          newName: Self.copyName(for: url.lastPathComponent, in: destination), options: options)
                    _ = try await TransferEngine(job: job, progress: progress, reportsTotal: false,
                                                 prompts: prompts).run()
                }
                if !others.isEmpty {
                    let job = TransferJob(kind: moving ? .move : .copy, sources: others, destination: destination, newName: nil,
                                          options: options)
                    _ = try await TransferEngine(job: job, progress: progress, reportsTotal: false,
                                                 prompts: prompts).run()
                }
                return urls
            }
            load(directory, selecting: urls.first?.lastPathComponent)
            finished?()
        }
    }

    /// "name copy.ext", "name copy 2.ext", … — the first name not taken in `folder`.
    nonisolated static func copyName(for name: String, in folder: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 1... {
            let candidate = index == 1 ? "\(base) copy" : "\(base) copy \(index)"
            let full = ext.isEmpty ? candidate : candidate + "." + ext
            if !FileManager.default.fileExists(atPath: folder.appending(path: full).path) {
                return full
            }
        }
        return name
    }

    /// Copies the names of the selected entries to the clipboard, one per line.
    @objc(cm_CopyNamesToClip:)
    func copyNamesToClip(_ sender: Any?) {
        copyToClipboard(selectedItems.map(\.name))
    }

    /// ⌥⌘C: copies the full paths of the selected entries, like Finder's "Copy as Pathname".
    @objc(cm_CopyFullNamesToClip:)
    func copyFullNamesToClip(_ sender: Any?) {
        let prefix = archive.map { $0.displayPath + "/" }
        copyToClipboard(selectedItems.map { item in prefix.map { $0 + item.name } ?? item.url.path })
    }

    /// Files → Print File List: the entries shown (the marked ones, when some are).
    @objc(cm_PrintDir:)
    func printDir(_ sender: Any?) {
        printList(subfolders: false)
    }

    /// Files → Print File List with Subfolders: the files inside the folders too.
    @objc(cm_PrintDirSub:)
    func printDirSub(_ sender: Any?) {
        printList(subfolders: true)
    }

    private func printList(subfolders: Bool) {
        let items = listView.marked.isEmpty ? listView.items : selectedItems
        Printing.print(Printing.list(items, in: directory, subfolders: subfolders && archive == nil && remote == nil),
                       title: panelView.pathBar.path, in: view.window)
    }

    /// Files → Print File: the text of the file under the cursor.
    @objc(cm_PrintFile:)
    func printFile(_ sender: Any?) {
        guard archive == nil, remote == nil, let item = listView.currentItem, !item.isParent, !item.isDirectory,
              let data = try? Data(contentsOf: item.url, options: .alwaysMapped), TextDecoding.looksLikeText(data) else {
            NSSound.beep()
            return
        }
        Printing.print(TextDecoding.string(from: data), title: item.name, in: view.window)
    }

    /// Ctrl+Z: the Finder comment of the file under the cursor, changed (empty:
    /// removed); the Comment column shows it.
    @objc(cm_CommentFiles:)
    func commentFiles(_ sender: Any?) {
        guard archive == nil, remote == nil, let item = listView.currentItem, !item.isParent,
              let window = view.window else {
            NSSound.beep()
            return
        }
        Prompt.text(String(localized: "Comment"), message: String(localized: "The comment of \u{201C}\(item.name)\u{201D}:"),
                    initial: FinderComment.read(item.url) ?? "", okTitle: String(localized: "OK"), in: window) {
            [weak self] text in
            do {
                try FinderComment.write(text.trimmingCharacters(in: .whitespacesAndNewlines), to: item.url)
                MetadataCache.shared.forget(item.url)
                self?.listView.needsDisplay = true
            } catch {
                Prompt.error(String(localized: "Cannot change the comment"), error, in: window)
            }
        }
    }

    /// The names (or full paths) with the size, the modification date and the
    /// permissions, tab-separated, one entry per line (a folder's size when calculated).
    @objc(cm_CopyDetailsToClip:)
    func copyDetailsToClip(_ sender: Any?) {
        copyToClipboard(selectedItems.map { details(of: $0, fullPath: false) })
    }

    @objc(cm_CopyFullDetailsToClip:)
    func copyFullDetailsToClip(_ sender: Any?) {
        copyToClipboard(selectedItems.map { details(of: $0, fullPath: true) })
    }

    private static let detailsDateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func details(of item: FileItem, fullPath: Bool) -> String {
        let name = fullPath ? archive.map { $0.displayPath + "/" + item.name } ?? item.url.path : item.name
        let size = item.isFolder ? listView.folderSizes[item.name].map(String.init) ?? "" : String(item.size)
        let kind = item.isSymlink ? "l" : item.isDirectory ? "d" : "-"
        return [name, size, Self.detailsDateFormat.string(from: item.modified), kind + item.permissions]
            .joined(separator: "\t")
    }

    /// The names of the selected entries saved in a text file, one per line.
    @objc(cm_SaveSelectionToFile:)
    func saveSelectionToFile(_ sender: Any?) {
        let names = selectedItems.map(\.name)
        guard !names.isEmpty else {
            NSSound.beep()
            return
        }
        chooseFile(saving: String(localized: "selection.txt")) { [weak self] url in
            do {
                try (names.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Prompt.error(String(localized: "Cannot save the selection"), error, in: self?.view.window)
            }
        }
    }

    /// Selects the entries named in a text file (names, or paths of this folder's entries).
    @objc(cm_LoadSelectionFromFile:)
    func loadSelectionFromFile(_ sender: Any?) {
        chooseFile(saving: nil) { [weak self] url in
            do {
                self?.select(lines: try String(contentsOf: url, encoding: .utf8))
            } catch {
                Prompt.error(String(localized: "Cannot read the selection"), error, in: self?.view.window)
            }
        }
    }

    /// Selects the entries named on the clipboard, one per line.
    @objc(cm_LoadSelectionFromClip:)
    func loadSelectionFromClip(_ sender: Any?) {
        guard let text = AppDefaults.pasteboard.string(forType: .string) else {
            NSSound.beep()
            return
        }
        select(lines: text)
    }

    /// Marks the entries shown whose names (or paths in this folder) are lines of `text`.
    private func select(lines text: String) {
        let folder = directory.standardizedFileURL.path
        let names = Set(text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("/") else { return line.isEmpty ? nil : line }
            let url = URL(filePath: line).standardizedFileURL
            return url.deletingLastPathComponent().path == folder ? url.lastPathComponent : nil
        })
        let shown = listView.items.filter { !$0.isParent && names.contains($0.name) }.map(\.name)
        guard !shown.isEmpty else {
            NSSound.beep()
            return
        }
        listView.setMarked(Set(shown))
        updateStatus()
    }

    /// A file to save to (with a suggested name) or to open, chosen in a sheet;
    /// a test run gives it with `file:/path`.
    private func chooseFile(saving name: String?, then use: @escaping (URL) -> Void) {
        #if DEBUG
        if let path = DebugAutomation.takeChosenFile() {
            use(URL(filePath: path))
            return
        }
        #endif
        guard let window = view.window else { return }
        let panel: NSSavePanel
        if let name {
            panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [.plainText]
        } else {
            let open = NSOpenPanel()
            open.allowsMultipleSelection = false
            open.canChooseDirectories = false
            panel = open
        }
        panel.directoryURL = remote == nil && archive == nil ? directory : nil
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { use(url) }
        }
    }

    func copyToClipboard(_ lines: [String]) {
        guard !lines.isEmpty else {
            NSSound.beep()
            return
        }
        let pasteboard = AppDefaults.pasteboard
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

}
