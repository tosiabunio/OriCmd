import AppKit

extension NSMenuItem {
    /// Keeps an image that tells items apart (a tag's color, an application, a
    /// volume) visible: from macOS 27 AppKit hides menu item images unless asked.
    func keepsImageVisible() {
        if #available(macOS 27, *) {
            preferredImageVisibility = .visible
        }
    }
}
