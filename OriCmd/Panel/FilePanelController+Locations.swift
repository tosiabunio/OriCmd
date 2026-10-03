import AppKit
import os

/// Locations and the state kept for each folder tab.
extension FilePanelController {
    /// Where the panel is inside an archive, while browsing one.
    struct ArchiveLocation {
        let url: URL
        var folder: String
        var entries: [ArchiveEntry]
        /// Size and date of the archive file when `entries` were read.
        var stamp: [Int64] = []
        /// For an archive inside an archive: the outer one, as it was shown. `url` is
        /// then a temporary copy, so the archive is read-only.
        var outer: OuterArchive?

        /// The archive itself, as the path bar shows it (outer.zip/inner.zip inside another).
        var rootPath: String { outer.map { $0.location.displayPath + "/" + $0.name } ?? url.path }

        var displayPath: String { folder.isEmpty ? rootPath : rootPath + "/" + folder }

        /// Whether files can be added, renamed or deleted in it.
        var isWritable: Bool { outer == nil && ArchiveEditor.isWritable(url) }

        /// Archive paths of entries shown in the current folder.
        func path(of name: String) -> String {
            folder.isEmpty ? name : folder + "/" + name
        }
    }

    /// The archive an archive inside it was opened from, and that one's name there.
    final class OuterArchive {
        let location: ArchiveLocation
        let name: String

        init(location: ArchiveLocation, name: String) {
            self.location = location
            self.name = name
        }
    }

    struct HistoryEntry {
        let directory: URL
        let selectedName: String?
    }

    /// A folder tab: everything that differs between tabs of one panel.
    struct Tab {
        /// Finds the tab again after an asynchronous question (indices may change).
        let id = UUID()
        var directory: URL
        var selectedName: String?
        var sortOrder: SortOrder
        var backHistory: [HistoryEntry] = []
        var forwardHistory: [HistoryEntry] = []
        /// The server shown in the tab, with its terminal: both stay while other tabs
        /// are shown (`directory` is the local folder the tab goes back to).
        var remote: RemoteLocation?
        var terminal: ShellTerminalView?
        var showsTerminal = false
        var lock = Lock.none
        /// The folder a locked tab keeps (or comes back to).
        var lockedDirectory: URL?
        /// A name given to the tab, shown instead of its folder's.
        var name: String?

        /// Total Commander's locked tabs: one that keeps its folder (going elsewhere
        /// opens a new tab), or one that comes back to it when chosen again.
        enum Lock: Int {
            case none, locked, allowsChanges
        }

        /// The folder's name (or the server folder's), or the tab's own; a locked tab
        /// is marked with *, as in Total Commander.
        var title: String {
            let folder: String
            if let remote {
                let name = (remote.path as NSString).lastPathComponent
                folder = name.isEmpty || name == "/" ? remote.fileSystem.displayName : name
            } else {
                folder = directory.path == "/" ? "/" : directory.lastPathComponent
            }
            return (lock == .none ? "" : "*") + (name ?? folder)
        }

        /// The folder's own icon (Downloads, Desktop, an app's folder…) on the startup
        /// disk; elsewhere a plain folder, as asking a network volume can be slow.
        var icon: NSImage {
            if remote != nil {
                return Self.symbol("network")
            }
            let path = directory.path
            guard !path.hasPrefix("/Volumes/") else { return Self.folderIcon }
            if let icon = Self.icons[path] { return icon }
            var isFolder: ObjCBool = false
            let icon = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
                ? NSWorkspace.shared.icon(forFile: path) : Self.folderIcon
            Self.icons[path] = icon
            return icon
        }

        private static var icons: [String: NSImage] = [:]
        private static let folderIcon = NSWorkspace.shared.icon(for: .folder)

        private static func symbol(_ name: String) -> NSImage {
            NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? folderIcon
        }
    }

}
