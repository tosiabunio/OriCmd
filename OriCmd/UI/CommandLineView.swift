import AppKit

/// The command line under the panels: "<current path>>" prompt and an input box.
final class CommandLineView: NSView {
    /// 26 pt, taller for the regular-size field of a larger panel font.
    static var height: CGFloat { Settings.isModern ? max(26, Theme.lineHeight(Theme.headerDetailFont) + 12) : 26 }

    let promptLabel = NSTextField(labelWithString: "")
    let inputField = NSComboBox()

    /// "/Users/me/Projects>", or in the modern look "~/Projects>".
    var directory: URL? {
        didSet {
            let path = directory?.path ?? ""
            promptLabel.stringValue = (Settings.isModern ? (path as NSString).abbreviatingWithTildeInPath : path) + ">"
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        promptLabel.lineBreakMode = .byTruncatingHead
        promptLabel.alignment = .right
        promptLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        promptLabel.setContentHuggingPriority(.required, for: .horizontal)

        inputField.completes = false
        applyLook()
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for view in [promptLabel, inputField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            promptLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            promptLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5),
            inputField.leadingAnchor.constraint(equalTo: promptLabel.trailingAnchor, constant: 2),
            inputField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            inputField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// The modern look's prompt in grey at the panel header's detail size, and the
    /// command typed in the system's monospaced font at that size; Total Commander's
    /// look keeps both at 11 pt.
    func applyLook() {
        let modern = Settings.isModern
        let size = Theme.headerDetailFont.pointSize
        promptLabel.font = modern ? Theme.headerDetailFont : Theme.chromeFont
        promptLabel.textColor = modern ? .secondaryLabelColor : .labelColor
        inputField.font = modern ? .monospacedSystemFont(ofSize: size, weight: .regular) : Theme.chromeFont
        inputField.controlSize = modern && size >= 13 ? .regular : .small
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
