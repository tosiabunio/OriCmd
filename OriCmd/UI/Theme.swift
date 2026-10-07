import AppKit

/// Visual constants of the panels in both looks (Settings → Panels): the modern one,
/// drawn as current Mac lists are, and Total Commander's, adapted to light and dark
/// appearance.
enum Theme {
    static var panelFont: NSFont { Settings.panelFont }

    /// Marked files' names: bold when so chosen in Settings → Colors.
    static func font(marked: Bool) -> NSFont {
        guard marked, ColorSettings.boldMarked else { return panelFont }
        return NSFontManager.shared.convert(panelFont, toHaveTrait: .boldFontMask)
    }

    /// The panel font with fixed-width digits, for sizes and dates.
    static var panelNumberFont: NSFont {
        let font = panelFont
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    static let chromeFont = NSFont.systemFont(ofSize: 11)

    /// Row height follows the panel font and the density: 22 pt for the standard
    /// 13 pt font, 19 pt for the compact 12 pt one.
    static var rowHeight: CGFloat {
        let font = panelFont
        let padding: CGFloat = Settings.density == .standard ? 6 : 4
        return max(ceil(font.ascender - font.descender + font.leading) + padding, 16)
    }

    /// In the modern look rows are rounded and inset from the list's edges: the
    /// highlight by `rowInset`, the columns a little further, by `contentInset`.
    static var rowInset: CGFloat { Settings.isModern ? 6 : 0 }
    static var contentInset: CGFloat { Settings.isModern ? 8 : 0 }

    /// A row's background or highlight: rounded in the modern look.
    static func rowPath(_ rect: NSRect, inset: CGFloat = rowInset) -> NSBezierPath {
        guard Settings.isModern else { return NSBezierPath(rect: rect) }
        return NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: 0), xRadius: 5, yRadius: 5)
    }

    /// Dates as the panels show them, the same way on every row in both looks: the
    /// region's short date and time, e.g. "27/09/2026, 11:30".
    static func dateText(_ date: Date) -> String {
        dates.string(from: date)
    }

    private static let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let panelBackground = NSColor.textBackgroundColor
    static let panelText = NSColor.textColor
    /// Marked (selected) files are drawn in red, as in Total Commander,
    /// unless another color is chosen in Settings.
    static var markedText: NSColor { ColorSettings.markedColor ?? defaultMarkedText }
    static var cursorBackground: NSColor { ColorSettings.cursorColor ?? .selectedContentBackgroundColor }
    static var cursorText: NSColor { ColorSettings.cursorTextColor ?? .alternateSelectedControlTextColor }
    /// Every other row in Full view when "alternating rows" is on.
    static let alternateRowBackground = NSColor.alternatingContentBackgroundColors.count > 1
        ? NSColor.alternatingContentBackgroundColors[1] : NSColor.controlBackgroundColor

    private static let defaultMarkedText = dynamic(
        light: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 0.4, blue: 0.4, alpha: 1)
    )
    static let markedCursorText = NSColor.systemYellow
    static let inactiveCursorFrame = NSColor.secondaryLabelColor
    /// The modern look's cursor in the other panel, or while OriCmd is in the
    /// background, as unfocused Mac lists show their selection.
    static let unfocusedCursorBackground = NSColor.unemphasizedSelectedContentBackgroundColor
    /// Marked rows are tinted lightly in the modern look, more with Increase Contrast.
    static var markedRowBackground: NSColor {
        markedText.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.22 : 0.09)
    }
    /// Ext, Size, Date and the other columns after Name in the modern look.
    static let secondaryText = NSColor.secondaryLabelColor

    static let activeHeaderBackground = NSColor.selectedContentBackgroundColor
    static let activeHeaderText = NSColor.alternateSelectedControlTextColor
    static let inactiveHeaderBackground = NSColor.unemphasizedSelectedContentBackgroundColor
    static let inactiveHeaderText = NSColor.textColor

    static let chromeBackground = NSColor.windowBackgroundColor
    static let chromeText = NSColor.controlTextColor
    static let separator = NSColor.separatorColor

    nonisolated private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
