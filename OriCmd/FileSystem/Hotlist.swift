import Foundation

/// Total Commander's "directory hotlist": favourite folders shared by both panels.
enum Hotlist {
    private static let key = "DirectoryHotlist"
    /// Posted when the list changes (the sidebar shows it).
    static let didChange = Notification.Name("OriCmdHotlistDidChange")

    static var directories: [String] {
        AppDefaults.store.stringArray(forKey: key) ?? []
    }

    static func set(_ list: [String]) {
        AppDefaults.store.set(list, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Adds `path`, or removes it if it is already listed.
    static func toggle(_ path: String) {
        var list = directories
        if let index = list.firstIndex(of: path) {
            list.remove(at: index)
        } else {
            list.append(path)
        }
        set(list)
    }
}
