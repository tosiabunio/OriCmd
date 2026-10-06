import AppKit

/// The main window's content: the sidebar and the panels. The sidebar is the
/// system's (glass on macOS 26, translucent before); ⌃⌘S or the toolbar shows or
/// hides it, and the choice is kept (Settings.showsSidebar).
final class RootSplitViewController: NSSplitViewController {
    let main = MainViewController()
    let sidebar = SidebarViewController()
    private lazy var sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)

    init() {
        super.init(nibName: nil, bundle: nil)
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = !Settings.showsSidebar
        addSplitViewItem(sidebarItem)
        let content = NSSplitViewItem(viewController: main)
        content.minimumThickness = 480
        addSplitViewItem(content)

        sidebar.onOpen = { [weak self] url, other in self?.main.open(url, inOtherPanel: other) }
        sidebar.menuProvider = { [weak self] url, isVolume in self?.main.placeMenu(for: url, isVolume: isVolume) }
        main.onLocationChange = { [weak self] url in self?.sidebar.reveal(url) }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)), name: Settings.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static let widthKey = "SidebarWidth"
    private var didAppear = false

    /// The sidebar comes back as wide as it was left (200 points at first).
    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didAppear else { return }
        didAppear = true
        let saved = AppDefaults.store.double(forKey: Self.widthKey)
        if !sidebarItem.isCollapsed {
            splitView.setPosition(saved >= 150 ? saved : 200, ofDividerAt: 0)
        }
    }

    /// Choosing a look shows or hides the sidebar with it.
    @objc private func settingsDidChange(_ notification: Notification) {
        if sidebarItem.isCollapsed == Settings.showsSidebar {
            sidebarItem.animator().isCollapsed = !Settings.showsSidebar
        }
    }

    /// Keeps whether the sidebar is shown (by ⌃⌘S, the toolbar or a drag).
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        let shown = !sidebarItem.isCollapsed
        if shown != Settings.showsSidebar {
            Settings.showsSidebar = shown
        }
        if didAppear, shown, sidebar.view.frame.width >= 150 {
            AppDefaults.store.set(Double(sidebar.view.frame.width), forKey: Self.widthKey)
        }
    }

    var isSidebarShown: Bool { !sidebarItem.isCollapsed }
}

extension NSWindow {
    /// The panels of the main window, whichever controller holds them.
    var mainViewController: MainViewController? {
        (contentViewController as? MainViewController) ?? (contentViewController as? RootSplitViewController)?.main
    }
}
