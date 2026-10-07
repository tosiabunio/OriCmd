import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnails for the Thumbnails view, generated on demand and cached.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private static let limit = 2000

    /// A file's thumbnail as it is drawn: plain, or as the Finder shows it.
    private struct Key: Hashable {
        let url: URL
        let asIcon: Bool
    }

    private var images: [Key: NSImage] = [:]
    private var pending: Set<Key> = []

    /// The cached thumbnail, or nil while it is generated; `ready` runs once it is.
    /// `asIcon`: as the Finder's icon view shows it — a document as a page with its
    /// edge and shadow, a picture with a border — rather than the bare picture.
    func thumbnail(for url: URL, size: CGFloat, asIcon: Bool = false,
                   ready: @escaping @MainActor () -> Void) -> NSImage? {
        let key = Key(url: url, asIcon: asIcon)
        if let image = images[key] { return image }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all
        )
        request.iconMode = asIcon
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let cgImage = representation?.cgImage
            Task { @MainActor in
                self.pending.remove(key)
                if self.images.count > Self.limit { self.images.removeAll() }
                self.images[key] = cgImage.map { NSImage(cgImage: $0, size: .zero) }
                    ?? NSWorkspace.shared.icon(forFile: url.path)
                ready()
            }
        }
        return nil
    }
}
