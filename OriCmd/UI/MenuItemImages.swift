import AppKit

extension NSMenuItem {
    /// Keeps an image that tells items apart (a tag's color, an application, a
    /// volume) visible: from macOS 27 AppKit hides menu item images unless asked.
    /// The property exists only in the macOS 27 SDK (Swift 6.4, Xcode 27); built with
    /// an older SDK, as on CI, the app has nothing to ask.
    func keepsImageVisible() {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            preferredImageVisibility = .visible
        }
        #endif
    }
}
