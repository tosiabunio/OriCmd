import AppKit
import UniformTypeIdentifiers

/// Small file icons, cached by extension (packages by path).
enum FileIcons {
    private static let size = NSSize(width: 16, height: 16)
    private static var byExtension: [String: NSImage] = [:]
    private static var byPackagePath: [String: NSImage] = [:]

    private static let folder = sized(NSWorkspace.shared.icon(for: .folder))
    private static let parent = NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: "Parent folder")
        ?? folder

    static func icon(for item: FileItem) -> NSImage {
        if item.isParent { return parent }
        if item.isFolder { return item.tagColor == 0 ? folder : folder(tagColor: item.tagColor) }
        if item.isPackage {
            return cached(&byPackagePath, item.url.path) { NSWorkspace.shared.icon(forFile: item.url.path) }
        }
        let ext = item.fileExtension.lowercased()
        return cached(&byExtension, ext) {
            NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
    }

    private static var tintedFolders: [String: NSImage] = [:]

    /// The folder icon in the color of a tag (a label number) at `size`, its shading kept,
    /// as the Finder colors tagged folders; the plain icon for no color.
    static func folder(tagColor: Int, size: NSSize = size) -> NSImage {
        let base = size == Self.size ? folder : NSWorkspace.shared.icon(for: .folder)
        let colors = NSWorkspace.shared.fileLabelColors
        guard tagColor > 0, colors.indices.contains(tagColor) else { return base }
        let color = colors[tagColor]
        let key = "\(tagColor) \(Int(size.width))"
        if let image = tintedFolders[key] { return image }
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            // The icon takes the color's hue and keeps its own light and shade; drawn
            // again over it, the icon's outline cuts away what fell outside it.
            color.setFill()
            rect.fill(using: .color)
            base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        tintedFolders[key] = image
        return image
    }

    private static func cached(_ cache: inout [String: NSImage], _ key: String, _ make: () -> NSImage) -> NSImage {
        if let image = cache[key] { return image }
        let image = sized(make())
        cache[key] = image
        return image
    }

    private static func sized(_ image: NSImage) -> NSImage {
        image.size = size
        return image
    }
}
