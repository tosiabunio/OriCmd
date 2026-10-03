import AppKit
import os

/// Browsing and changing the archive shown by a panel.
extension FilePanelController {
    // MARK: - Archives

    /// Shows the contents of an archive as a folder (Enter / Ctrl+PgDn on it).
    /// Shows an archive as a folder. It is read in the background (a big tar.gz is
    /// decompressed as a whole), and a folder load still under way is dropped.
    /// `quietly`: a file tried as an archive whatever its name (Ctrl+PgDn); if it is
    /// none, nothing happens.
    func openArchive(_ url: URL, inside outer: OuterArchive? = nil, folder: String = "", selecting name: String? = nil,
                     quietly: Bool = false) {
        if archive == nil { leaveLockedTab(for: nil) }
        loadGeneration += 1
        let generation = loadGeneration
        // A folder still loading is dropped, with its indicator; Esc stops this one.
        loadTask?.cancel()
        loadTask = Task {
            let showsIndicator = Task {
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled && generation == loadGeneration { panelView.setLoading(true) }
            }
            defer {
                showsIndicator.cancel()
                if generation == loadGeneration {
                    panelView.setLoading(false)
                    loadTask = nil
                }
            }
            do {
                let (entries, stamp) = try await Self.readArchive(url)
                // An empty file passes for an empty archive: not unless named as one.
                guard !entries.isEmpty || !quietly else { throw CancellationError() }
                guard generation == loadGeneration else { return }
                listView.setMarked([])
                // A folder asked for that the archive does not have: its root.
                let known = folder.isEmpty || entries.contains { $0.path == folder || $0.path.hasPrefix(folder + "/") }
                archive = ArchiveLocation(url: url, folder: known ? folder : "", entries: entries, stamp: stamp, outer: outer)
                showArchiveFolder(selecting: known ? name : nil)
            } catch {
                // An archive in an archive was a temporary copy.
                if outer != nil { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                guard generation == loadGeneration, !quietly else { return }
                Prompt.error(String(localized: "Cannot open archive \u{201C}\(url.lastPathComponent)\u{201D}"), error,
                             in: view.window)
            }
        }
    }

    /// Shows here what the other panel `source` has under its cursor (Ctrl+Left/Right):
    /// a folder or an archive opened, a file in its folder, selected. Without
    /// `underCursor`, the folder (or archive folder) `source` shows. A server's folders
    /// and archives inside archives (temporary copies) stay where they are.
    func show(locationOf source: FilePanelController, underCursor: Bool) {
        let item = underCursor ? source.listView.currentItem : nil
        if source.remote != nil || source.archive?.outer != nil {
            NSSound.beep()
        } else if let archive = source.archive {
            var folder = archive.folder
            var name: String?
            if let item, item.isParent {
                guard !folder.isEmpty else {
                    load(archive.url.deletingLastPathComponent(), selecting: archive.url.lastPathComponent)
                    return
                }
                name = (folder as NSString).lastPathComponent
                folder = (folder as NSString).deletingLastPathComponent
            } else if let item, item.isDirectory {
                folder = archive.path(of: item.name)
            } else {
                name = item?.name
            }
            load(archive.url.deletingLastPathComponent(), selecting: archive.url.lastPathComponent) { [weak self] in
                self?.openArchive(archive.url, folder: folder, selecting: name)
            }
        } else if let item, item.isParent {
            load(source.directory.deletingLastPathComponent(), selecting: source.directory.lastPathComponent)
        } else if let item, item.isFolder {
            load(item.url)
        } else if let item {
            // Also a file of search results or the branch view: its own folder.
            let folder = item.url.deletingLastPathComponent()
            if !item.isDirectory, ArchiveReader.isArchive(item.name) {
                load(folder, selecting: item.url.lastPathComponent) { [weak self] in self?.openArchive(item.url) }
            } else {
                load(folder, selecting: item.url.lastPathComponent)
            }
        } else {
            load(source.directory)
        }
    }

    /// Reads the archive again, unless it has not changed since (the folder
    /// holding it may change for other reasons).
    func reopenArchive(_ location: ArchiveLocation, selecting name: String? = nil, force: Bool = false) {
        if !force, !location.stamp.isEmpty, Self.stamp(of: location.url) == location.stamp {
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            let result = try? await Self.readArchive(location.url)
            guard generation == loadGeneration, archive?.url == location.url else { return }
            guard let (entries, stamp) = result else {
                load(directory)
                return
            }
            archive?.entries = entries
            archive?.stamp = stamp
            showArchiveFolder(selecting: name ?? listView.currentItem?.name)
        }
    }

    @concurrent
    private nonisolated static func readArchive(_ url: URL) async throws -> ([ArchiveEntry], [Int64]) {
        let stamp = stamp(of: url)
        return (try ArchiveReader.entries(of: url), stamp)
    }

    nonisolated static func stamp(of url: URL) -> [Int64] {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return [] }
        return [Int64(info.st_size), Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec)]
    }

    /// Changes the archive shown in this panel (with a progress sheet), then
    /// shows its new contents. `completion` receives whether it succeeded.
    func applyArchiveEdit(_ edit: ArchiveEditor.Edit, selecting name: String? = nil,
                          completion: ((Bool) -> Void)? = nil) {
        guard let archive, let window = view.window else { return }
        let url = archive.url
        Task {
            // An encrypted archive is changed with its password (and keeps it).
            let password: String?
            do {
                password = try await ArchivePasswords.password(for: url, entries: archive.entries, in: window)
            } catch {
                if !(error is CancellationError) {
                    Prompt.error(String(localized: "Cannot update archive"), error, in: window)
                }
                completion?(false)
                return
            }
            let controller = TransferController(title: String(localized: "Updating archive"),
                                                failureTitle: String(localized: "Cannot update archive"), window: window)
            let done = await controller.run(source: url.path, target: url.path) { progress, _ in
                do {
                    try await ArchiveEditor.apply(edit, to: url, password: password, progress: progress)
                } catch let error as ArchiveError where error.kind == .wrongPassword {
                    await ArchivePasswords.forget(url)
                    throw error
                }
                return [url]
            }
            if let current = self.archive, current.url == url {
                reopenArchive(current, selecting: name, force: true)
            }
            completion?(!done.isEmpty)
        }
    }

    /// Lists the current archive folder. Folders that only exist implicitly
    /// (as part of deeper paths) are shown too.
    func showArchiveFolder(selecting name: String?) {
        guard let archive else { return }
        let prefix = archive.folder.isEmpty ? "" : archive.folder + "/"
        var children: [String: FileItem] = [:]
        // The order the archive has its entries in (for Unsorted).
        var order: [String] = []
        for entry in archive.entries where entry.path.hasPrefix(prefix) && entry.path.count > prefix.count {
            let rest = entry.path.dropFirst(prefix.count)
            let childName = String(rest.prefix { $0 != "/" })
            let isNested = rest.contains("/")
            if isNested && children[childName] != nil { continue }
            if children[childName] == nil { order.append(childName) }
            let isFolder = isNested || entry.isDirectory
            children[childName] = FileItem(
                name: childName, url: archive.url.appending(path: prefix + childName),
                isDirectory: isFolder, isPackage: false, isSymlink: false, isHidden: childName.hasPrefix("."),
                size: isFolder ? 0 : entry.size, modified: entry.modified,
                mode: isNested ? 0o755 : entry.mode
            )
        }
        entries = order.compactMap { children[$0] }
        entriesOrder = nil
        panelView.show(directory: directory, volumes: Volume.mounted())
        updatePathBar()
        refreshList(selecting: name, fallback: 0)
        delegate?.filePanelDidChangeDirectory(self)
    }

    /// `asArchive`: Ctrl+PgDn, the file is tried as an archive whatever its name.
    func openInArchive(_ item: FileItem, asArchive: Bool = false) {
        guard let archive else { return }
        if item.isParent {
            archiveGoUp()
        } else if item.isDirectory {
            self.archive?.folder = archive.path(of: item.name)
            showArchiveFolder(selecting: nil)
        } else if ArchiveReader.isArchive(item.name) || asArchive {
            // An archive in the archive opens as a folder too, from a temporary copy —
            // unless the panel went elsewhere while it was being extracted.
            let generation = loadGeneration
            Task {
                guard let url = await extractToTemporaryFolder(item) else { return }
                guard generation == loadGeneration, self.archive?.url == archive.url,
                      self.archive?.folder == archive.folder else {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                    return
                }
                openArchive(url, inside: OuterArchive(location: archive, name: item.name),
                            quietly: !ArchiveReader.isArchive(item.name))
            }
        } else {
            Task {
                if let url = await extractToTemporaryFolder(item) {
                    openFile(url)
                }
            }
        }
    }

    /// Up one folder inside the archive, or out of it at its root.
    func archiveGoUp() {
        guard let archive else { return }
        if archive.folder.isEmpty, let outer = archive.outer {
            // Back to the outer archive; the temporary copy of this one goes.
            try? FileManager.default.removeItem(at: archive.url.deletingLastPathComponent())
            self.archive = outer.location
            showArchiveFolder(selecting: outer.name)
        } else if archive.folder.isEmpty {
            load(archive.url.deletingLastPathComponent(), selecting: archive.url.lastPathComponent, recordingHistory: false)
        } else {
            let name = (archive.folder as NSString).lastPathComponent
            self.archive?.folder = (archive.folder as NSString).deletingLastPathComponent
            showArchiveFolder(selecting: name)
        }
    }

    /// Extracts one entry of the archive into a new temporary folder.
    func extractToTemporaryFolder(_ item: FileItem) async -> URL? {
        guard let archive else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "OriCmd-\(UUID().uuidString)")
        let path = archive.path(of: item.name)
        do {
            let password = try await ArchivePasswords.password(
                for: archive.url, entries: ArchivePasswords.entries(archive.entries, at: [path]), in: view.window)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try await ArchiveReader.extract(archive.url, paths: [path], base: archive.folder, to: folder,
                                                password: password, progress: TransferProgress())
            } catch let error as ArchiveError where error.kind == .wrongPassword {
                ArchivePasswords.forget(archive.url)
                throw error
            }
            return folder.appending(path: item.name)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: folder)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: folder)
            Prompt.error(String(localized: "Cannot unpack \u{201C}\(item.name)\u{201D}"), error, in: view.window)
            return nil
        }
    }

    /// Refuses changes inside archives that cannot be written (rar, iso, …).
    func refuseReadOnlyArchive() -> Bool {
        guard let archive, !archive.isWritable else { return false }
        if archive.outer != nil {
            Prompt.info(String(localized: "An archive inside an archive is read-only"),
                        message: String(localized: "Copy it out of the outer archive (F5) to change it."), in: view.window)
            return true
        }
        Prompt.info(String(localized: "This archive is read-only"),
                    message: String(localized: "Only zip, tar, tar.gz, tar.bz2, tar.xz and 7z archives can be changed."),
                    in: view.window)
        return true
    }

    /// Refuses operations that are never available inside archives.
    func refuseInsideArchive() -> Bool {
        if remote != nil {
            Prompt.info(String(localized: "Not supported on servers"),
                        message: String(localized: "Download the files first (F5)."), in: view.window)
            return true
        }
        guard archive != nil else { return false }
        Prompt.info(String(localized: "Not supported inside archives"),
                    message: String(localized: "Unpack the files first (F5), or use Alt+F5 to create a new archive."),
                    in: view.window)
        return true
    }

}
