import AppKit

/// The current path line above a file list, e.g. "/Users/me/*.*".
/// Highlighted when its panel is the active one. A click on a parent folder in it
/// goes there; a click on the current folder, the mask or right of them makes it
/// editable. In the compact header (Settings) it also holds the volume, which a
/// click chooses, and its free space, which opens drive information; the mask shows
/// only when it filters.
final class PathBar: NSView {
    var path = "" {
        didSet { layoutDidChange() }
    }

    /// A parent folder in `path`, which a click goes to: where it is in the text
    /// (UTF-16 offsets) and its name.
    struct Crumb: Equatable {
        let range: NSRange
        let name: String
    }

    /// The parents in `path` a click goes to, from the root. The current folder is
    /// not one of them: a click on it edits the path.
    var crumbs: [Crumb] = [] {
        didSet { layoutDidChange() }
    }

    var isActive = false {
        didSet { needsDisplay = true }
    }

    /// Appends the file mask ("*.*", or the panel filter), as Total Commander does.
    var showsMask = true {
        didSet { layoutDidChange() }
    }

    var mask = "*.*" {
        didSet { layoutDidChange() }
    }

    /// Both filtering rules and the number of matching entries, excluding the parent row.
    var filterSummary: String? {
        didSet { toolTip = filterSummary; layoutDidChange() }
    }
    var filterCriteria = ""
    var filterCount = ""
    var onClearFilters: (() -> Void)?

    /// The volume of the folder shown, as a button at the start (compact header only).
    var volume: (name: String, icon: NSImage)? {
        didSet { layoutDidChange() }
    }

    /// "… free", shown at the end when the whole path fits beside it (compact header only).
    var freeSpace = "" {
        didSet { layoutDidChange() }
    }

    /// Leaves room at the end for the spinner of a folder being read (compact header only).
    var isLoading = false {
        didSet { if isLoading != oldValue { layoutDidChange() } }
    }

    private var isCompact: Bool { Settings.compactPanelHeader }

    var onClick: (() -> Void)?
    /// A click on the volume: the menu of volumes.
    var onVolumeClick: (() -> Void)?
    /// A click on the free and total capacity: information about the current volume.
    var onDriveInformation: (() -> Void)?
    /// A click on a crumb, or its choice in the menu of those put away into "…".
    var onCrumbClick: ((Int) -> Void)?
    /// The text to edit when the bar is clicked (the path without the mask).
    var editableText: (() -> String)?
    /// Enter in the field: go there.
    var onCommit: ((String) -> Void)?
    /// The names Tab completes the typed text to (full texts, "/" after folders).
    var completions: ((String) async -> [String])?

    private var field: NSTextField?

    /// What a click at a point does, besides editing.
    private enum Link: Equatable {
        case crumb(Int)
        /// The "…" standing for parents that did not fit.
        case ellipsis
        case volume
        case driveInformation
        case clearFilter
    }

    /// Underlined under the mouse.
    private var hovered: Link? {
        didSet {
            toolTip = hovered == .driveInformation ? String(localized: "Drive Information") : filterSummary
            if hovered != oldValue { needsDisplay = true }
        }
    }
    /// Tab cycling: the text before it began, its candidates, the one shown (-1: their
    /// common start) and the text shown.
    private var cycle: (base: String, candidates: [String], index: Int, shown: String)?

    var isEditing: Bool { field != nil }

    nonisolated override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: isCompact ? 22 : 18) }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        return [
            .font: Theme.panelFont,
            .foregroundColor: isActive ? Theme.activeHeaderText : Theme.inactiveHeaderText,
            .paragraphStyle: paragraph,
        ]
    }

    /// What is drawn (the path, or the end of it after "…" when it does not fit) and
    /// where its links are.
    private struct Layout {
        var text: String
        /// Crumbs before this one are put away into "…".
        var firstShown = 0
        /// Where a crumb's range in `path` begins in `text`, less where it begins in `path`.
        var shift = 0
        var ellipsis: NSRect?
        var crumbRects: [Int: NSRect] = [:]
        /// Where the path is drawn, between the volume and what is at the end.
        var textX: CGFloat = 4
        var textWidth: CGFloat = 0
        var volume: NSRect?
        var filter: NSRect?
        var freeSpace: NSRect?
    }

    private static let chipFont = NSFont.systemFont(ofSize: 11)
    private static let chipIconSize: CGFloat = 14
    private static let spinnerRoom: CGFloat = 22

    private var chipAttributes: [NSAttributedString.Key: Any] {
        [.font: Self.chipFont, .foregroundColor: isActive ? Theme.activeHeaderText : Theme.inactiveHeaderText]
    }

    /// The width of the volume button: icon, name and a chevron.
    private func volumeWidth(_ name: String) -> CGFloat {
        6 + Self.chipIconSize + 4 + ceil((name as NSString).size(withAttributes: chipAttributes).width) + 4 + 8 + 6
    }

    /// The width of the filter chip: a funnel and the mask.
    private var filterWidth: CGFloat {
        6 + 12 + 3 + ceil(((filterSummary ?? mask) as NSString).size(withAttributes: chipAttributes).width) + (filterSummary == nil ? 6 : 24)
    }

    /// Whether the mask filters anything (it is shown in the compact header only then).
    private var filters: Bool { showsMask && mask != "*.*" }

    /// Leading parents give way to "…" until the rest fits, as Total Commander cuts a
    /// long path at its start; when even the current folder does not fit, its start
    /// is cut too. The free space gives way first.
    private func makeLayout() -> Layout {
        let attributes = attributes
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: attributes).width }
        let full = showsMask && !isCompact && filterSummary == nil ? (path.hasSuffix("/") ? path : path + "/") + mask : path
        var layout = Layout(text: full)
        var leading: CGFloat = 4, trailing = bounds.maxX - 4
        var volumeRect: NSRect?, filterRect: NSRect?, freeRect: NSRect?
        if isCompact {
            let chipHeight = bounds.height - 4
            if let volume {
                volumeRect = NSRect(x: 2, y: 2, width: volumeWidth(volume.name), height: chipHeight)
                leading = volumeRect!.maxX + 6
            }
            if isLoading { trailing -= Self.spinnerRoom }
        }
        if filterSummary != nil || (isCompact && filters) {
            let chipWidth = min(filterWidth, max(60, min(bounds.width * 0.60, trailing - leading - 24)))
            filterRect = NSRect(x: trailing - chipWidth, y: 1, width: chipWidth, height: bounds.height - 2)
            trailing = filterRect!.minX - 6
        }
        if isCompact {
            let freeWidth = ceil((freeSpace as NSString).size(withAttributes: chipAttributes).width)
            if !freeSpace.isEmpty, !isLoading, width(full) <= trailing - leading - freeWidth - 12 {
                freeRect = NSRect(x: trailing - freeWidth, y: 0, width: freeWidth, height: bounds.height)
                trailing = freeRect!.minX - 12
            }
        }
        let available = max(trailing - leading, 0)
        if width(full) > available, !crumbs.isEmpty {
            for hidden in 1...crumbs.count {
                let end = NSMaxRange(crumbs[hidden - 1].range)
                let rest = (full as NSString).substring(from: end)
                let ellipsis = rest.hasPrefix("/") ? "…" : "…/"
                layout = Layout(text: ellipsis + rest, firstShown: hidden, shift: (ellipsis as NSString).length - end)
                if width(layout.text) <= available { break }
            }
            layout.ellipsis = NSRect(x: leading - 4, y: 0, width: 4 + width("…"), height: bounds.height)
        }
        layout.textX = leading
        layout.textWidth = available
        layout.volume = volumeRect
        layout.filter = filterRect
        layout.freeSpace = freeRect
        guard width(layout.text) <= available else { return layout }
        let text = layout.text as NSString
        for index in layout.firstShown..<crumbs.count {
            let range = NSRange(location: crumbs[index].range.location + layout.shift, length: crumbs[index].range.length)
            guard range.location >= 0, NSMaxRange(range) <= text.length else { continue }
            layout.crumbRects[index] = NSRect(x: leading + width(text.substring(to: range.location)), y: 0,
                                              width: width(text.substring(with: range)), height: bounds.height)
        }
        return layout
    }

    private func link(at point: NSPoint, in layout: Layout) -> Link? {
        guard !isEditing else { return nil }
        if let clear = clearRect(in: layout), clear.contains(point) { return .clearFilter }
        if let volume = layout.volume, volume.contains(point) { return .volume }
        if let freeSpace = layout.freeSpace, freeSpace.contains(point) { return .driveInformation }
        if let ellipsis = layout.ellipsis, ellipsis.contains(point) { return .ellipsis }
        return layout.crumbRects.first { $0.value.contains(point) }.map { .crumb($0.key) }
    }

    /// Where the volume button is, if it is shown (the volume menu opens under it).
    var volumeRect: NSRect? { makeLayout().volume }
    var freeSpaceRect: NSRect? { makeLayout().freeSpace }

    private func clearRect(in layout: Layout) -> NSRect? {
        guard filterSummary != nil, let rect = layout.filter else { return nil }
        return NSRect(x: rect.maxX - 22, y: rect.minY, width: 22, height: rect.height)
    }

    var filterClearRect: NSRect? { clearRect(in: makeLayout()) }

    override func draw(_ dirtyRect: NSRect) {
        (isActive ? Theme.activeHeaderBackground : Theme.inactiveHeaderBackground).setFill()
        bounds.fill()

        let layout = makeLayout()
        drawAccessories(layout)
        let text = NSMutableAttributedString(string: layout.text, attributes: attributes)
        switch hovered {
        case .crumb(let index) where layout.crumbRects[index] != nil:
            let range = crumbs[index].range
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                              range: NSRange(location: range.location + layout.shift, length: range.length))
        case .ellipsis:
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 1))
        default:
            break
        }
        let height = text.size().height
        text.draw(in: NSRect(x: layout.textX, y: (bounds.height - height) / 2, width: layout.textWidth, height: height))
    }

    /// The volume button, the filter chip and the free space of the compact header.
    private func drawAccessories(_ layout: Layout) {
        let textColor = isActive ? Theme.activeHeaderText : Theme.inactiveHeaderText
        let chipFill = isActive ? NSColor.white.withAlphaComponent(0.18) : NSColor.quaternaryLabelColor
        let textHeight = ceil(Self.chipFont.ascender - Self.chipFont.descender)
        func symbol(_ name: String, size: CGFloat, in rect: NSRect) {
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [textColor.withAlphaComponent(0.8)]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            image.draw(in: NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }

        if let rect = layout.volume, let volume {
            (hovered == .volume ? chipFill.withAlphaComponent(chipFill.alphaComponent * 1.8) : chipFill).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            volume.icon.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - Self.chipIconSize / 2,
                                        width: Self.chipIconSize, height: Self.chipIconSize),
                             from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let nameX = rect.minX + 6 + Self.chipIconSize + 4
            (volume.name as NSString).draw(
                with: NSRect(x: nameX, y: rect.midY - textHeight / 2, width: rect.maxX - nameX - 18, height: textHeight),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: chipAttributes)
            symbol("chevron.down", size: 7, in: NSRect(x: rect.maxX - 14, y: rect.minY, width: 8, height: rect.height))
        }
        if let rect = layout.filter {
            chipFill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            symbol("line.3.horizontal.decrease", size: 8, in: NSRect(x: rect.minX + 6, y: rect.minY, width: 12, height: rect.height))
            let clear = clearRect(in: layout)
            let countWidth = filterSummary == nil ? 0 : ceil((filterCount as NSString).size(withAttributes: chipAttributes).width)
            let countX = (clear?.minX ?? rect.maxX) - 4 - countWidth
            ((filterSummary == nil ? mask : filterCriteria) as NSString).draw(
                with: NSRect(x: rect.minX + 21, y: rect.midY - textHeight / 2,
                             width: max(0, countX - rect.minX - 27), height: textHeight),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: chipAttributes)
            if filterSummary != nil {
                (filterCount as NSString).draw(at: NSPoint(x: countX, y: rect.midY - textHeight / 2), withAttributes: chipAttributes)
            }
            if let clear {
                if hovered == .clearFilter {
                    textColor.withAlphaComponent(0.15).setFill()
                    NSBezierPath(ovalIn: clear.insetBy(dx: 3, dy: 1)).fill()
                }
                symbol("xmark", size: 8, in: clear)
            }
        }
        if let rect = layout.freeSpace {
            var attributes = chipAttributes
            attributes[.foregroundColor] = textColor.withAlphaComponent(0.7)
            if hovered == .driveInformation { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            (freeSpace as NSString).draw(at: NSPoint(x: rect.minX, y: rect.midY - textHeight / 2), withAttributes: attributes)
        }
    }

    /// The menu of the parents put away into "…", from the root, each as its whole path.
    func hiddenCrumbsMenu() -> NSMenu? {
        let layout = makeLayout()
        guard layout.firstShown > 0 else { return nil }
        let menu = NSMenu()
        for index in 0..<layout.firstShown {
            let title = (path as NSString).substring(to: NSMaxRange(crumbs[index].range))
            let item = NSMenuItem(title: title, action: #selector(hiddenCrumbChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    @objc private func hiddenCrumbChosen(_ sender: NSMenuItem) {
        onCrumbClick?(sender.tag)
    }

    /// Where a crumb is shown, if it is (for test runs).
    func crumbRect(_ index: Int) -> NSRect? {
        makeLayout().crumbRects[index]
    }

    private func layoutDidChange() {
        hovered = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutDidChange()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func resetCursorRects() {
        guard !isEditing else { return }
        let layout = makeLayout()
        for rect in Array(layout.crumbRects.values) + [layout.ellipsis, layout.volume, layout.freeSpace, clearRect(in: layout)].compactMap(\.self) {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = link(at: convert(event.locationInWindow, from: nil), in: makeLayout())
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
    }

    /// A click follows a parent or header action; elsewhere it turns the path into
    /// a field (Enter goes there, Esc cancels, Tab completes).
    override func mouseDown(with event: NSEvent) {
        let link = link(at: convert(event.locationInWindow, from: nil), in: makeLayout())
        onClick?()
        switch link {
        case .crumb(let index):
            onCrumbClick?(index)
        case .ellipsis:
            hiddenCrumbsMenu()?.popUp(positioning: nil, at: NSPoint(x: makeLayout().textX - 4, y: bounds.maxY), in: self)
        case .volume:
            onVolumeClick?()
        case .driveInformation:
            onDriveInformation?()
        case .clearFilter:
            onClearFilters?()
        case nil:
            beginEditing()
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { String(localized: "Path") }
    override func accessibilityValue() -> Any? { path }

    /// For VoiceOver each parent is a button, those put away into "…" too.
    override func accessibilityChildren() -> [Any]? {
        let layout = makeLayout()
        let buttons = crumbs.indices.compactMap { index -> CrumbElement? in
            guard let frame = layout.crumbRects[index] ?? layout.ellipsis else { return nil }
            let element = CrumbElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(String(localized: "Go to \(crumbs[index].name)"))
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            element.press = { [weak self] in
                self?.onClick?()
                self?.onCrumbClick?(index)
            }
            return element
        }
        var volumeButton: [CrumbElement] = []
        if let frame = layout.volume, let volume {
            let element = CrumbElement()
            element.setAccessibilityRole(.popUpButton)
            element.setAccessibilityLabel(String(localized: "Volume"))
            element.setAccessibilityValue(volume.name)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            element.press = { [weak self] in
                self?.onClick?()
                self?.onVolumeClick?()
            }
            volumeButton.append(element)
        }
        if let frame = clearRect(in: layout) {
            let element = CrumbElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(String(localized: "Clear filters"))
            element.setAccessibilityValue(filterSummary)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            element.press = { [weak self] in
                self?.onClick?()
                self?.onClearFilters?()
            }
            volumeButton.append(element)
        }
        if let frame = layout.freeSpace, !isEditing {
            let element = CrumbElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(String(localized: "Drive Information"))
            element.setAccessibilityValue(freeSpace)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            element.press = { [weak self] in
                self?.onClick?()
                self?.onDriveInformation?()
            }
            volumeButton.append(element)
        }
        return (super.accessibilityChildren() ?? []) + volumeButton + buttons
    }

    func beginEditing() {
        guard field == nil, let text = editableText?() else { return }
        let field = NSTextField(string: text)
        field.font = Theme.panelFont
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.frame = bounds
        field.autoresizingMask = [.width, .height]
        addSubview(field)
        self.field = field
        layoutDidChange()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    /// Ends editing, going to the typed text on commit.
    func endEditing(commit: Bool) {
        guard let field else { return }
        let text = field.stringValue
        self.field = nil
        cycle = nil
        field.delegate = nil
        field.removeFromSuperview()
        layoutDidChange()
        if commit {
            onCommit?(text)
        } else {
            onClick?()
        }
    }

    /// Tab: completes to what the candidates have in common, then goes through them.
    private func complete(backwards: Bool) {
        guard let field, let completions else { return }
        if var cycle, cycle.candidates.contains(field.stringValue) || field.stringValue == cycle.shown {
            let count = cycle.candidates.count
            // From the common start (index -1) Tab takes the first, Shift+Tab the last.
            cycle.index = cycle.index < 0 ? (backwards ? count - 1 : 0) : (cycle.index + (backwards ? -1 : 1) + count) % count
            cycle.shown = cycle.candidates[cycle.index]
            self.cycle = cycle
            show(cycle.shown, in: field)
            return
        }
        let typed = field.stringValue
        Task {
            let candidates = await completions(typed)
            guard self.field === field, field.stringValue == typed, !candidates.isEmpty else {
                if candidates.isEmpty { NSSound.beep() }
                return
            }
            let common = Self.commonPrefix(of: candidates)
            if candidates.count == 1 {
                cycle = nil
                show(candidates[0], in: field)
            } else if common.count > typed.count {
                // The common start, which may be one of the names itself: the next Tab
                // goes on from there.
                let index = candidates.firstIndex(of: common) ?? -1
                cycle = (typed, candidates, index, common)
                show(common, in: field)
            } else {
                let index = backwards ? candidates.count - 1 : 0
                cycle = (typed, candidates, index, candidates[index])
                show(candidates[index], in: field)
            }
        }
    }

    private func show(_ text: String, in field: NSTextField) {
        field.stringValue = text
        field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    /// The longest start the texts share, ignoring letter case (as the file system does).
    private static func commonPrefix(of texts: [String]) -> String {
        guard var prefix = texts.first else { return "" }
        for text in texts.dropFirst() {
            while !text.lowercased().hasPrefix(prefix.lowercased()) { prefix.removeLast() }
        }
        return prefix
    }
}

/// A parent folder in the path bar as VoiceOver sees it: a button that goes there.
nonisolated private final class CrumbElement: NSAccessibilityElement {
    var press: @MainActor () -> Void = {}

    /// Accessibility asks on the main thread.
    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated { press() }
        return true
    }
}

extension PathBar: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false)
        case #selector(NSResponder.insertTab(_:)):
            complete(backwards: false)
        case #selector(NSResponder.insertBacktab(_:)):
            complete(backwards: true)
        default:
            return false
        }
        return true
    }

    /// Clicking elsewhere cancels.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard field != nil else { return }
        endEditing(commit: false)
    }
}
