import AppKit

/// The release version and fork identity in a compact About window.
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        let name = ProcessInfo.processInfo.processName
        window.title = String(localized: "About \(name)")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let localBuild = info["OriCmdForkBuild"] as? String ?? ""
        let build = localBuild.isEmpty ? info["CFBundleVersion"] as? String ?? "" : localBuild
        let versionLabel = NSTextField(labelWithString: build.isEmpty ? version : "\(version) (\(build))")
        versionLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)

        let fork = info["OriCmdFork"] as? String ?? "tosiabunio"
        // The fork's release identity stays the same in every interface language.
        let forkLabel = NSTextField(labelWithString: "\(fork) fork")
        forkLabel.font = .systemFont(ofSize: 13)
        forkLabel.textColor = .secondaryLabelColor
        for label in [versionLabel, forkLabel] {
            label.alignment = .center
            label.isSelectable = true
        }

        let stack = NSStackView(views: [versionLabel, forkLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        window.contentView = content
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
    }
}
