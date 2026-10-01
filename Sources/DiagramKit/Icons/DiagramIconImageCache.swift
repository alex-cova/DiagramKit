import AppKit
import Foundation

/// Loads SVG (or PDF/PNG) diagram icons and caches rasterized `NSImage`s.
/// Bound cache keeps decode cost predictable on large architecture diagrams.
@MainActor
public final class DiagramIconImageCache {
    public static let shared = DiagramIconImageCache()

    /// Soft cap on cached rasterizations (key = path|pointSize).
    private let maxEntries = 128
    private var cache: [String: NSImage] = [:]
    private var insertionOrder: [String] = []

    public func image(at url: URL, pointSize: CGFloat = 64) -> NSImage? {
        let key = "\(url.path)|\(Int(pointSize))"
        if let cached = cache[key] {
            // Refresh LRU order.
            if let idx = insertionOrder.firstIndex(of: key) {
                insertionOrder.remove(at: idx)
                insertionOrder.append(key)
            }
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let sized = NSImage(size: NSSize(width: pointSize, height: pointSize))
        sized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        sized.unlockFocus()
        cache[key] = sized
        insertionOrder.append(key)
        trimIfNeeded()
        return sized
    }

    public func clear() {
        cache.removeAll()
        insertionOrder.removeAll()
    }

    private func trimIfNeeded() {
        while cache.count > maxEntries, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
    public init() {}
}
